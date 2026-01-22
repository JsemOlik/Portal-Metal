//
//  Renderer.m
//  Portal
//
//  Created by Oliver Steiner on 22.01.2026.
//

#import <simd/simd.h>
#import <ModelIO/ModelIO.h>

#import "Renderer.h"
#import "Player.h"
#import "World.h"
#import "Camera.h"
#import "Portal.h"

// Include header shared between C code here, which executes Metal API commands, and .metal files
#import "ShaderTypes.h"

// The renderer works with MaxBuffersInFlight at the same time.
#define MaxBuffersInFlight 3

@implementation Renderer
{
    dispatch_semaphore_t _inFlightSemaphore;
    id <MTLDevice> _device;

    id <MTLBuffer> _dynamicUniformBuffer[MaxBuffersInFlight];
    id <MTLBuffer> _perObjectUniformBuffers[MaxBuffersInFlight][8]; // 8 meshes max (room for expansion)
    id <MTLRenderPipelineState> _pipelineState;
    id <MTLRenderPipelineState> _portalPipelineState;
    id <MTLDepthStencilState> _depthState;
    id <MTLTexture> _colorMap;
    MTLVertexDescriptor *_mtlVertexDescriptor;

    uint8_t _uniformBufferIndex;

    matrix_float4x4 _projectionMatrix;



    id<MTL4CommandQueue> _commandQueue4;
    id<MTL4CommandAllocator> _commandAllocators[MaxBuffersInFlight];
    id<MTL4CommandBuffer> _commandBuffer;
    id<MTL4ArgumentTable> _argumentTable;
    id<MTLResidencySet> _residencySet;
    id<MTLSharedEvent> _sharedEvent;
    uint64_t _currentFrameIndex;

    // Game systems
    Player _player;
    World _world;
    PortalPair _portals;
    CFTimeInterval _lastFrameTime;

    // Input tracking - using raw key codes for reliability
    BOOL _keysPressed[128];  // Raw key codes (0-127)
    float _mouseDeltaX;
    float _mouseDeltaY;
    BOOL _mouseTrackingEnabled;
}

-(nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)view;
{
    self = [super init];
    if(self)
    {
        _device = view.device;
        _inFlightSemaphore = dispatch_semaphore_create(MaxBuffersInFlight);
        [self _loadMetalWithView:view];
        [self _loadAssets];

        // Initialize player at center of world, at proper eye height above ground
        // Floor is at y=-10, top surface at y=-9.75, eye height is 1.8, so camera at -9.75 + 1.8 = -7.95
        _player = player_create((vector_float3){0, -7.95, 0});

        // Create the world
        _world = world_create(_device, _mtlVertexDescriptor);

        // Initialize portal system
        _portals = portal_pair_create();

        // Initialize input tracking
        memset(_keysPressed, 0, sizeof(_keysPressed));
        _mouseDeltaX = 0.0f;
        _mouseDeltaY = 0.0f;
        _mouseTrackingEnabled = NO;
        _lastFrameTime = CFAbsoluteTimeGetCurrent();

        NSLog(@"Player initialized at position: (%.2f, %.2f, %.2f)",
              _player.camera.position.x, _player.camera.position.y, _player.camera.position.z);
        NSLog(@"Portal system initialized - Left click: Blue, Right click: Orange");
    }

    return self;
}

- (void)_loadMetalWithView:(nonnull MTKView *)view;
{
    /// Load Metal state objects and initialize renderer dependent view properties

    view.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
    view.colorPixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
    view.sampleCount = 1;

    _mtlVertexDescriptor = [[MTLVertexDescriptor alloc] init];

    _mtlVertexDescriptor.attributes[VertexAttributePosition].format = MTLVertexFormatFloat3;
    _mtlVertexDescriptor.attributes[VertexAttributePosition].offset = 0;
    _mtlVertexDescriptor.attributes[VertexAttributePosition].bufferIndex = BufferIndexMeshPositions;

    _mtlVertexDescriptor.attributes[VertexAttributeTexcoord].format = MTLVertexFormatFloat2;
    _mtlVertexDescriptor.attributes[VertexAttributeTexcoord].offset = 0;
    _mtlVertexDescriptor.attributes[VertexAttributeTexcoord].bufferIndex = BufferIndexMeshGenerics;

    _mtlVertexDescriptor.layouts[BufferIndexMeshPositions].stride = 12;
    _mtlVertexDescriptor.layouts[BufferIndexMeshPositions].stepRate = 1;
    _mtlVertexDescriptor.layouts[BufferIndexMeshPositions].stepFunction = MTLVertexStepFunctionPerVertex;

    _mtlVertexDescriptor.layouts[BufferIndexMeshGenerics].stride = 8;
    _mtlVertexDescriptor.layouts[BufferIndexMeshGenerics].stepRate = 1;
    _mtlVertexDescriptor.layouts[BufferIndexMeshGenerics].stepFunction = MTLVertexStepFunctionPerVertex;

    id<MTLLibrary> defaultLibrary = [_device newDefaultLibrary];

    id<MTL4Compiler> compiler = [_device newCompilerWithDescriptor:[MTL4CompilerDescriptor new]
                                                            error:nil];

    MTL4LibraryFunctionDescriptor *vertexFunction = [MTL4LibraryFunctionDescriptor new];
    vertexFunction.library = defaultLibrary;
    vertexFunction.name = @"vertexShader";
    MTL4LibraryFunctionDescriptor *fragmentFunction = [MTL4LibraryFunctionDescriptor new];
    fragmentFunction.library = defaultLibrary;
    fragmentFunction.name = @"fragmentShader";

    MTL4RenderPipelineDescriptor *pipelineStateDescriptor = [MTL4RenderPipelineDescriptor new];
    pipelineStateDescriptor.label = @"MyPipeline";
    pipelineStateDescriptor.rasterSampleCount = view.sampleCount;
    pipelineStateDescriptor.vertexFunctionDescriptor = vertexFunction;
    pipelineStateDescriptor.fragmentFunctionDescriptor = fragmentFunction;
    pipelineStateDescriptor.vertexDescriptor = _mtlVertexDescriptor;
    pipelineStateDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat;

    NSError *error = NULL;
    _pipelineState = [compiler newRenderPipelineStateWithDescriptor:pipelineStateDescriptor
                                                compilerTaskOptions:nil
                                                              error:&error];

    if (!_pipelineState)
    {
        NSLog(@"Failed to created pipeline state, error %@", error);
    }

    // Create portal pipeline with alpha blending
    MTL4LibraryFunctionDescriptor *portalFragmentFunction = [MTL4LibraryFunctionDescriptor new];
    portalFragmentFunction.library = defaultLibrary;
    portalFragmentFunction.name = @"portalFragmentShader";

    MTL4RenderPipelineDescriptor *portalPipelineDesc = [MTL4RenderPipelineDescriptor new];
    portalPipelineDesc.label = @"PortalPipeline";
    portalPipelineDesc.rasterSampleCount = view.sampleCount;
    portalPipelineDesc.vertexFunctionDescriptor = vertexFunction;
    portalPipelineDesc.fragmentFunctionDescriptor = portalFragmentFunction;
    portalPipelineDesc.vertexDescriptor = _mtlVertexDescriptor;
    portalPipelineDesc.colorAttachments[0].pixelFormat = view.colorPixelFormat;
    // TODO: Add alpha blending once we figure out Metal 4 API

    _portalPipelineState = [compiler newRenderPipelineStateWithDescriptor:portalPipelineDesc
                                                       compilerTaskOptions:nil
                                                                     error:&error];

    if (!_portalPipelineState)
    {
        NSLog(@"Failed to create portal pipeline state, error %@", error);
    }

    MTLDepthStencilDescriptor *depthStateDesc = [[MTLDepthStencilDescriptor alloc] init];
    depthStateDesc.depthCompareFunction = MTLCompareFunctionLess;
    depthStateDesc.depthWriteEnabled = YES;
    _depthState = [_device newDepthStencilStateWithDescriptor:depthStateDesc];

    for(NSUInteger i = 0; i < MaxBuffersInFlight; i++)
    {
        _dynamicUniformBuffer[i] = [_device newBufferWithLength:sizeof(Uniforms)
                                                        options:MTLResourceStorageModeShared];

        _dynamicUniformBuffer[i].label = @"UniformBuffer";

        // Create per-object uniform buffers
        for(NSUInteger j = 0; j < 8; j++)
        {
            _perObjectUniformBuffers[i][j] = [_device newBufferWithLength:sizeof(Uniforms)
                                                                   options:MTLResourceStorageModeShared];
            _perObjectUniformBuffers[i][j].label = [NSString stringWithFormat:@"PerObjectUniform[%lu][%lu]", i, j];
        }
    }

    _commandQueue4 = [_device newMTL4CommandQueue];
    _commandBuffer = [_device newCommandBuffer];
    MTL4ArgumentTableDescriptor *atd = [MTL4ArgumentTableDescriptor new];
    atd.maxBufferBindCount = 3;
    atd.maxTextureBindCount = 1;
    _argumentTable = [_device newArgumentTableWithDescriptor:atd error:nil];
    MTLResidencySetDescriptor *residencySetDesc = [MTLResidencySetDescriptor new];
    _residencySet = [_device newResidencySetWithDescriptor:residencySetDesc error:nil];
    for(uint32_t i = 0 ; i < MaxBuffersInFlight ; i++)
    {
        _commandAllocators[i] = [_device newCommandAllocator];
    }
    [_commandQueue4 addResidencySet:_residencySet];

    /// Run MaxBuffersInFlight ahead to simplify checking for completed frames
    _currentFrameIndex = MaxBuffersInFlight;
    _sharedEvent = [_device newSharedEvent];
    [_sharedEvent setSignaledValue:MaxBuffersInFlight-1];
}

- (void)_loadAssets
{
    /// Load assets into metal objects

    NSError *error;

    MTKTextureLoader* textureLoader = [[MTKTextureLoader alloc] initWithDevice:_device];

    NSDictionary *textureLoaderOptions =
    @{
      MTKTextureLoaderOptionTextureUsage       : @(MTLTextureUsageShaderRead),
      MTKTextureLoaderOptionTextureStorageMode : @(MTLStorageModePrivate)
      };

    _colorMap = [textureLoader newTextureWithName:@"ColorMap"
                                      scaleFactor:1.0
                                           bundle:nil
                                          options:textureLoaderOptions
                                            error:&error];

    if(!_colorMap || error)
    {
        NSLog(@"Error creating texture %@", error.localizedDescription);
    }


    for(NSUInteger i = 0; i < MaxBuffersInFlight; i++)
    {
        [_residencySet addAllocation:_dynamicUniformBuffer[i]];

        // Add per-object buffers to residency set
        for(NSUInteger j = 0; j < 8; j++)
        {
            [_residencySet addAllocation:_perObjectUniformBuffers[i][j]];
        }
    }
    [_residencySet addAllocation:_colorMap];

    // Add world meshes to residency set
    for (NSUInteger i = 0; i < _world.meshCount; i++) {
        WorldMesh worldMesh = _world.meshes[i];
        MTKMesh *mesh = worldMesh.mesh;

        for (NSUInteger bufferIndex = 0; bufferIndex < mesh.vertexBuffers.count; bufferIndex++)
        {
            MTKMeshBuffer *vertexBuffer = mesh.vertexBuffers[bufferIndex];
            if((NSNull*)vertexBuffer != [NSNull null])
            {
                [_residencySet addAllocation:vertexBuffer.buffer];
            }
        }

        for(MTKSubmesh *submesh in mesh.submeshes)
        {
            [_residencySet addAllocation:submesh.indexBuffer.buffer];
        }
    }
    [_residencySet commit];
}

- (void)_updateGameState
{
    /// Update any game state before encoding rendering commands to our drawable

    // Calculate delta time
    CFTimeInterval currentTime = CFAbsoluteTimeGetCurrent();
    CFTimeInterval deltaTime = currentTime - _lastFrameTime;
    _lastFrameTime = currentTime;

    // Cap delta time to prevent huge jumps (which could cause input to stick)
    if (deltaTime > 0.1) {
        deltaTime = 0.1;
    }

    // Gather input using raw key codes
    // Key codes: W=13, A=0, S=1, D=2, Space=49
    float moveInput[3] = {0, 0, 0};
    if (_keysPressed[13]) moveInput[2] += 1.0f;  // W
    if (_keysPressed[1])  moveInput[2] -= 1.0f;  // S
    if (_keysPressed[0])  moveInput[0] -= 1.0f;  // A
    if (_keysPressed[2])  moveInput[0] += 1.0f;  // D

    BOOL jump = _keysPressed[49];  // Space bar

    float mouseDelta[2] = {_mouseDeltaX, _mouseDeltaY};

    // Reset mouse delta after use
    _mouseDeltaX = 0.0f;
    _mouseDeltaY = 0.0f;

    // Get collision boxes from world
    NSUInteger collisionBoxCount = 0;
    AABB *collisionBoxes = world_get_collision_boxes(&_world, &collisionBoxCount);

    // Update player with collision detection and portal teleportation
    player_update(&_player, (float)deltaTime, moveInput, mouseDelta, jump, collisionBoxes, collisionBoxCount, &_portals);

    // Update uniforms for all meshes
    matrix_float4x4 viewMatrix = camera_view_matrix(_player.camera);

    for (NSUInteger i = 0; i < _world.meshCount; i++) {
        WorldMesh worldMesh = _world.meshes[i];
        Uniforms * uniforms = (Uniforms*)_perObjectUniformBuffers[_uniformBufferIndex][i].contents;
        uniforms->projectionMatrix = _projectionMatrix;
        uniforms->viewMatrix = viewMatrix;
        uniforms->modelMatrix = matrix4x4_translation(worldMesh.position.x, worldMesh.position.y, worldMesh.position.z);
    }
}

- (void)drawInMTKView:(nonnull MTKView *)view
{
    /// Per frame updates here
    _uniformBufferIndex = (_uniformBufferIndex + 1) % MaxBuffersInFlight;

    /// Wait for previous work to complete to be able to reset and reuse the allocator.
    uint32_t subFrameIndex = _currentFrameIndex % MaxBuffersInFlight;
    id<MTL4CommandAllocator> commandAllocatorForFrame = _commandAllocators[subFrameIndex];
    uint64_t previousValueToWaitFor = _currentFrameIndex - MaxBuffersInFlight;
    [_sharedEvent waitUntilSignaledValue:previousValueToWaitFor timeoutMS:10];
    [commandAllocatorForFrame reset];
    [_commandBuffer beginCommandBufferWithAllocator:commandAllocatorForFrame];

    [self _updateGameState];

    /// Delay getting the currentMTL4RenderPassDescriptor until absolutely needed. This avoids
    ///   holding onto the drawable and blocking the display pipeline any longer than necessary
    MTL4RenderPassDescriptor* renderPassDescriptor = view.currentMTL4RenderPassDescriptor;

    if(renderPassDescriptor != nil)
    {
        /// Final pass rendering code here
        id<MTL4RenderCommandEncoder> renderEncoder =
            [_commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];

        [renderEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
        [renderEncoder setCullMode:MTLCullModeBack];
        [renderEncoder setRenderPipelineState:_pipelineState];
        [renderEncoder setDepthStencilState:_depthState];

        // Render all world meshes
        for (NSUInteger i = 0; i < _world.meshCount; i++) {
            WorldMesh worldMesh = _world.meshes[i];
            MTKMesh *mesh = worldMesh.mesh;

            [renderEncoder pushDebugGroup:[NSString stringWithFormat:@"DrawMesh%lu", i]];

            [renderEncoder setArgumentTable:_argumentTable atStages:MTLRenderStageVertex | MTLRenderStageFragment];
            [_argumentTable setAddress:_perObjectUniformBuffers[_uniformBufferIndex][i].gpuAddress atIndex:BufferIndexUniforms];

            for (NSUInteger bufferIndex = 0; bufferIndex < mesh.vertexBuffers.count; bufferIndex++)
            {
                MTKMeshBuffer *vertexBuffer = mesh.vertexBuffers[bufferIndex];
                if((NSNull*)vertexBuffer != [NSNull null])
                {
                    [_argumentTable setAddress:vertexBuffer.buffer.gpuAddress + vertexBuffer.offset atIndex:bufferIndex];
                }
            }
            [_argumentTable setTexture:_colorMap.gpuResourceID atIndex:TextureIndexColor];

            for(MTKSubmesh *submesh in mesh.submeshes)
            {
                [renderEncoder drawIndexedPrimitives:submesh.primitiveType
                                           indexCount:submesh.indexCount
                                            indexType:submesh.indexType
                                          indexBuffer:submesh.indexBuffer.buffer.gpuAddress + submesh.indexBuffer.offset
                                    indexBufferLength:submesh.indexBuffer.buffer.length - submesh.indexBuffer.offset];
            }

            [renderEncoder popDebugGroup];
        }

        // Render active portals (render both if active)
        NSLog(@"=== Portal Rendering ===");
        NSLog(@"Blue active: %d, Orange active: %d, Linked: %d",
              _portals.blue.active, _portals.orange.active, _portals.linked);

        // TEMPORARY: Force render both portals for debugging
        NSLog(@"Rendering BLUE portal at (%.2f, %.2f, %.2f)",
              _portals.blue.position.x, _portals.blue.position.y, _portals.blue.position.z);
        [self renderPortal:&_portals.blue withEncoder:renderEncoder];

        NSLog(@"Rendering ORANGE portal at (%.2f, %.2f, %.2f)",
              _portals.orange.position.x, _portals.orange.position.y, _portals.orange.position.z);
        [self renderPortal:&_portals.orange withEncoder:renderEncoder];

        [renderEncoder endEncoding];

        [_commandBuffer useResidencySet:((CAMetalLayer *)view.layer).residencySet];
        [_commandBuffer endCommandBuffer];

        id<CAMetalDrawable> drawable = view.currentDrawable;
        [_commandQueue4 waitForDrawable:drawable];
        [_commandQueue4 commit:&_commandBuffer count:1];

        uint64_t futureValueToWaitFor = _currentFrameIndex;
        [_commandQueue4 signalEvent:_sharedEvent value:futureValueToWaitFor];
        _currentFrameIndex++;

        [_commandQueue4 signalDrawable:drawable];
        [drawable present];
    }
}

- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
    /// Respond to drawable size or orientation changes here

    float aspect = size.width / (float)size.height;
    _projectionMatrix = matrix_perspective_right_hand(65.0f * (M_PI / 180.0f), aspect, 0.1f, 100.0f);
}

#pragma mark Matrix Math Utilities

matrix_float4x4 matrix4x4_translation(float tx, float ty, float tz)
{
    return (matrix_float4x4) {{
        { 1,   0,  0,  0 },
        { 0,   1,  0,  0 },
        { 0,   0,  1,  0 },
        { tx, ty, tz,  1 }
    }};
}

static matrix_float4x4 matrix4x4_rotation(float radians, vector_float3 axis)
{
    axis = vector_normalize(axis);
    float ct = cosf(radians);
    float st = sinf(radians);
    float ci = 1 - ct;
    float x = axis.x, y = axis.y, z = axis.z;

    return (matrix_float4x4) {{
        { ct + x * x * ci,     y * x * ci + z * st, z * x * ci - y * st, 0},
        { x * y * ci - z * st,     ct + y * y * ci, z * y * ci + x * st, 0},
        { x * z * ci + y * st, y * z * ci - x * st,     ct + z * z * ci, 0},
        {                   0,                   0,                   0, 1}
    }};
}

matrix_float4x4 matrix_perspective_right_hand(float fovyRadians, float aspect, float nearZ, float farZ)
{
    float ys = 1 / tanf(fovyRadians * 0.5);
    float xs = ys / aspect;
    float zs = farZ / (nearZ - farZ);

    return (matrix_float4x4) {{
        { xs,   0,          0,  0 },
        {  0,  ys,          0,  0 },
        {  0,   0,         zs, -1 },
        {  0,   0, nearZ * zs,  0 }
    }};
}

- (void)handleKeyDown:(NSEvent *)event
{
    unsigned short keyCode = [event keyCode];

    // Handle ESC key to release mouse
    if (keyCode == 53) { // ESC
        if (_mouseTrackingEnabled) {
            _mouseTrackingEnabled = NO;
            [NSCursor unhide];
            CGAssociateMouseAndMouseCursorPosition(YES);
        }
        return;
    }

    // Handle Q key to clear all stuck keys (emergency fix)
    if (keyCode == 12) { // Q
        memset(_keysPressed, 0, sizeof(_keysPressed));
        NSLog(@"Cleared all key states (Q pressed)");
        return;
    }

    // Set key state using raw key code
    if (keyCode < 128) {
        _keysPressed[keyCode] = YES;
    }

    // Enable mouse tracking on first key press
    if (!_mouseTrackingEnabled) {
        _mouseTrackingEnabled = YES;
        [NSCursor hide];
        CGAssociateMouseAndMouseCursorPosition(NO);
    }
}

- (void)handleKeyUp:(NSEvent *)event
{
    unsigned short keyCode = [event keyCode];

    // Clear key state using raw key code
    if (keyCode < 128) {
        _keysPressed[keyCode] = NO;
    }
}

- (void)handleFocusLost
{
    // Clear all keys when window loses focus to prevent sticking
    memset(_keysPressed, 0, sizeof(_keysPressed));
}

- (void)handleMouseMove:(NSEvent *)event
{
    if (_mouseTrackingEnabled) {
        _mouseDeltaX += [event deltaX];
        _mouseDeltaY -= [event deltaY]; // Invert Y for natural camera movement
    }
}

- (void)handleMouseClick:(NSEvent *)event isRightClick:(BOOL)isRightClick
{
    // Shoot portal on mouse click
    PortalColor color = isRightClick ? PortalColorOrange : PortalColorBlue;

    // Create ray from camera
    vector_float3 forward = camera_forward(_player.camera);
    Ray ray = ray_create(_player.camera.position, forward);

    // Get world collision boxes
    NSUInteger collisionBoxCount = 0;
    AABB *collisionBoxes = world_get_collision_boxes(&_world, &collisionBoxCount);

    // Ray cast to find surface
    RayHitResult hit = ray_intersect_world(ray, collisionBoxes, collisionBoxCount, 100.0f);

    if (hit.hit) {
        // Place portal at hit location
        // Offset slightly from surface to prevent z-fighting
        vector_float3 portalPosition = hit.point + hit.normal * 0.01f;

        portal_pair_place(&_portals, color, portalPosition, hit.normal);

        NSLog(@"Placed %@ portal at (%.2f, %.2f, %.2f)",
              color == PortalColorBlue ? @"BLUE" : @"ORANGE",
              portalPosition.x, portalPosition.y, portalPosition.z);

        if (portal_pair_is_linked(&_portals)) {
            NSLog(@"Portals are now LINKED!");
        }
    } else {
        NSLog(@"No surface hit - can't place portal");
    }
}

- (void)renderPortal:(Portal *)portal withEncoder:(id<MTL4RenderCommandEncoder>)renderEncoder
{
    // TEMPORARY: Comment out active check for debugging
    // if (!portal->active) {
    //     NSLog(@"Portal not active, skipping render");
    //     return;
    // }

    NSString *colorName = portal->color == PortalColorBlue ? @"Blue" : @"Orange";
    NSLog(@"renderPortal called for %@ portal", colorName);

    [renderEncoder pushDebugGroup:[NSString stringWithFormat:@"Portal_%@", colorName]];

    // Switch to portal pipeline
    [renderEncoder setRenderPipelineState:_portalPipelineState];
    [renderEncoder setCullMode:MTLCullModeNone]; // Render both sides

    // Set up uniforms for portal
    Uniforms uniforms;
    uniforms.projectionMatrix = _projectionMatrix;
    uniforms.viewMatrix = camera_view_matrix(_player.camera);
    uniforms.modelMatrix = portal->transform;

    // Use last component of model matrix to pass portal color (0=blue, 1=orange)
    float colorFlag = portal->color == PortalColorOrange ? 1.0f : 0.0f;
    uniforms.modelMatrix.columns[3][3] = colorFlag;

    NSLog(@"Portal color: %@, colorFlag: %.2f", colorName, colorFlag);

    // Create temporary buffer for portal uniforms
    id<MTLBuffer> portalUniformBuffer = [_device newBufferWithBytes:&uniforms
                                                              length:sizeof(Uniforms)
                                                             options:MTLResourceStorageModeShared];

    [renderEncoder setArgumentTable:_argumentTable atStages:MTLRenderStageVertex | MTLRenderStageFragment];
    [_argumentTable setAddress:portalUniformBuffer.gpuAddress atIndex:BufferIndexUniforms];

    // Get portal mesh from world
    MTKMesh *portalMesh = _world.portalMesh;
    if (!portalMesh) {
        NSLog(@"ERROR: Portal mesh is NULL!");
        [renderEncoder popDebugGroup];
        return;
    }

    NSLog(@"Portal mesh vertex buffers: %lu", (unsigned long)portalMesh.vertexBuffers.count);

    // Set vertex buffers
    for (NSUInteger bufferIndex = 0; bufferIndex < portalMesh.vertexBuffers.count; bufferIndex++)
    {
        MTKMeshBuffer *vertexBuffer = portalMesh.vertexBuffers[bufferIndex];
        if((NSNull*)vertexBuffer != [NSNull null])
        {
            [_argumentTable setAddress:vertexBuffer.buffer.gpuAddress + vertexBuffer.offset atIndex:bufferIndex];
        }
    }

    // Draw portal mesh
    NSLog(@"Drawing portal with %lu submeshes", (unsigned long)portalMesh.submeshes.count);
    for(MTKSubmesh *submesh in portalMesh.submeshes)
    {
        NSLog(@"Drawing submesh with %lu indices", (unsigned long)submesh.indexCount);
        [renderEncoder drawIndexedPrimitives:submesh.primitiveType
                                   indexCount:submesh.indexCount
                                    indexType:submesh.indexType
                                  indexBuffer:submesh.indexBuffer.buffer.gpuAddress + submesh.indexBuffer.offset
                            indexBufferLength:submesh.indexBuffer.buffer.length - submesh.indexBuffer.offset];
    }

    NSLog(@"Finished rendering %@ portal", colorName);
    [renderEncoder popDebugGroup];
}

@end
