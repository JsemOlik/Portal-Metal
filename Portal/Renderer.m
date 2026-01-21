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

// Include header shared between C code here, which executes Metal API commands, and .metal files
#import "ShaderTypes.h"

// The renderer works with MaxBuffersInFlight at the same time.
#define MaxBuffersInFlight 3

@implementation Renderer
{
    dispatch_semaphore_t _inFlightSemaphore;
    id <MTLDevice> _device;

    id <MTLBuffer> _dynamicUniformBuffer[MaxBuffersInFlight];
    id <MTLRenderPipelineState> _pipelineState;
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
    CFTimeInterval _lastFrameTime;
    
    // Input tracking
    BOOL _keysPressed[256];
    NSPoint _lastMousePos;
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
        
        // Initialize player at center of world, 1 unit above ground
        _player = player_create((vector_float3){0, 1, 0});
        
        // Create the world
        _world = world_create(_device);
        
        // Initialize input tracking
        memset(_keysPressed, 0, sizeof(_keysPressed));
        _lastMousePos = NSMakePoint(0, 0);
        _lastFrameTime = CFAbsoluteTimeGetCurrent();
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

    MTLDepthStencilDescriptor *depthStateDesc = [[MTLDepthStencilDescriptor alloc] init];
    depthStateDesc.depthCompareFunction = MTLCompareFunctionLess;
    depthStateDesc.depthWriteEnabled = YES;
    _depthState = [_device newDepthStencilStateWithDescriptor:depthStateDesc];

    for(NSUInteger i = 0; i < MaxBuffersInFlight; i++)
    {
        _dynamicUniformBuffer[i] = [_device newBufferWithLength:sizeof(Uniforms)
                                                        options:MTLResourceStorageModeShared];

        _dynamicUniformBuffer[i].label = @"UniformBuffer";
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
    
    // Gather input
    float moveInput[3] = {0, 0, 0};
    if (_keysPressed['w'] || _keysPressed['W']) moveInput[2] += 1.0f;
    if (_keysPressed['s'] || _keysPressed['S']) moveInput[2] -= 1.0f;
    if (_keysPressed['a'] || _keysPressed['A']) moveInput[0] -= 1.0f;
    if (_keysPressed['d'] || _keysPressed['D']) moveInput[0] += 1.0f;
    
    float mouseDelta[2] = {0, 0}; // Updated in handleMouseMove
    
    // Update player
    player_update(&_player, (float)deltaTime, moveInput, mouseDelta);
    
    // Update uniforms
    Uniforms * uniforms = (Uniforms*)_dynamicUniformBuffer[_uniformBufferIndex].contents;
    uniforms->projectionMatrix = _projectionMatrix;
    uniforms->modelViewMatrix = camera_view_matrix(_player.camera);
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
            
            [renderEncoder pushDebugGroup:[NSString stringWithFormat:@"DrawWall%lu", i]];
            
            [renderEncoder setArgumentTable:_argumentTable atStages:MTLRenderStageVertex | MTLRenderStageFragment];
            [_argumentTable setAddress:_dynamicUniformBuffer[_uniformBufferIndex].gpuAddress atIndex:BufferIndexUniforms];
            
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
    NSString *chars = [event characters];
    if ([chars length] > 0) {
        unsigned short keyCode = [chars characterAtIndex:0];
        if (keyCode < 256) {
            _keysPressed[keyCode] = YES;
        }
    }
}

- (void)handleKeyUp:(NSEvent *)event
{
    NSString *chars = [event characters];
    if ([chars length] > 0) {
        unsigned short keyCode = [chars characterAtIndex:0];
        if (keyCode < 256) {
            _keysPressed[keyCode] = NO;
        }
    }
}

- (void)handleMouseMove:(NSEvent *)event
{
    // Mouse delta could be calculated from event location
    // This is a placeholder - the player update uses {0, 0} for mouse delta
}

@end
