//
//  World.m
//  Portal
//
//  Created by Oliver Steiner on 22.01.2026.
//

#import <Foundation/Foundation.h>
#import <MetalKit/MetalKit.h>
#import <ModelIO/ModelIO.h>
#import "World.h"

static MTKMesh* create_cube_mesh(id<MTLDevice> device, vector_float3 dimensions)
{
    MTKMeshBufferAllocator *allocator = [[MTKMeshBufferAllocator alloc] initWithDevice:device];
    
    MDLMesh *mdlMesh = [MDLMesh newBoxWithDimensions:dimensions
                                            segments:(vector_uint3){1, 1, 1}
                                        geometryType:MDLGeometryTypeTriangles
                                       inwardNormals:NO
                                           allocator:allocator];
    
    NSError *error;
    MTKMesh *mesh = [[MTKMesh alloc] initWithMesh:mdlMesh device:device error:&error];
    
    if (!mesh) {
        NSLog(@"Error creating cube mesh: %@", error.localizedDescription);
    }
    
    return mesh;
}

World world_create(id<MTLDevice> device)
{
    World world = {0};
    world.meshCount = 6; // 6 walls
    world.meshes = malloc(sizeof(WorldMesh) * world.meshCount);
    
    // Floor (y = -10)
    world.meshes[0] = (WorldMesh) {
        .mesh = create_cube_mesh(device, (vector_float3){40, 0.5, 40}),
        .position = (vector_float3){0, -10, 0},
        .scale = (vector_float3){1, 1, 1}
    };
    
    // Ceiling (y = 10)
    world.meshes[1] = (WorldMesh) {
        .mesh = create_cube_mesh(device, (vector_float3){40, 0.5, 40}),
        .position = (vector_float3){0, 10, 0},
        .scale = (vector_float3){1, 1, 1}
    };
    
    // Front wall (z = -20)
    world.meshes[2] = (WorldMesh) {
        .mesh = create_cube_mesh(device, (vector_float3){40, 20, 0.5}),
        .position = (vector_float3){0, 0, -20},
        .scale = (vector_float3){1, 1, 1}
    };
    
    // Back wall (z = 20)
    world.meshes[3] = (WorldMesh) {
        .mesh = create_cube_mesh(device, (vector_float3){40, 20, 0.5}),
        .position = (vector_float3){0, 0, 20},
        .scale = (vector_float3){1, 1, 1}
    };
    
    // Left wall (x = -20)
    world.meshes[4] = (WorldMesh) {
        .mesh = create_cube_mesh(device, (vector_float3){0.5, 20, 40}),
        .position = (vector_float3){-20, 0, 0},
        .scale = (vector_float3){1, 1, 1}
    };
    
    // Right wall (x = 20)
    world.meshes[5] = (WorldMesh) {
        .mesh = create_cube_mesh(device, (vector_float3){0.5, 20, 40}),
        .position = (vector_float3){20, 0, 0},
        .scale = (vector_float3){1, 1, 1}
    };
    
    return world;
}

void world_release(World *world)
{
    if (world->meshes) {
        free(world->meshes);
        world->meshes = NULL;
    }
    world->meshCount = 0;
}
