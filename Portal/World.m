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
#import "ShaderTypes.h"

static MTKMesh* create_cube_mesh(id<MTLDevice> device, vector_float3 dimensions, MTLVertexDescriptor *vertexDescriptor)
{
    MTKMeshBufferAllocator *allocator = [[MTKMeshBufferAllocator alloc] initWithDevice:device];

    MDLMesh *mdlMesh = [MDLMesh newBoxWithDimensions:dimensions
                                            segments:(vector_uint3){1, 1, 1}
                                        geometryType:MDLGeometryTypeTriangles
                                       inwardNormals:NO
                                           allocator:allocator];

    MDLVertexDescriptor *mdlVertexDescriptor = MTKModelIOVertexDescriptorFromMetal(vertexDescriptor);
    mdlVertexDescriptor.attributes[VertexAttributePosition].name = MDLVertexAttributePosition;
    mdlVertexDescriptor.attributes[VertexAttributeTexcoord].name = MDLVertexAttributeTextureCoordinate;
    mdlMesh.vertexDescriptor = mdlVertexDescriptor;

    NSError *error;
    MTKMesh *mesh = [[MTKMesh alloc] initWithMesh:mdlMesh device:device error:&error];

    if (!mesh) {
        NSLog(@"Error creating cube mesh: %@", error.localizedDescription);
    }

    return mesh;
}

World world_create(id<MTLDevice> device, MTLVertexDescriptor *vertexDescriptor)
{
    World world = {0};
    world.meshCount = 7; // 6 walls + 1 test cube
    world.meshes = malloc(sizeof(WorldMesh) * world.meshCount);

    // Create collision boxes for all static geometry (6 walls + 1 test cube)
    world.collisionBoxCount = 7;
    world.collisionBoxes = malloc(sizeof(AABB) * world.collisionBoxCount);

    // Floor (y = -10)
    world.meshes[0] = (WorldMesh) {
        .mesh = create_cube_mesh(device, (vector_float3){40, 0.5, 40}, vertexDescriptor),
        .position = (vector_float3){0, -10, 0},
        .scale = (vector_float3){1, 1, 1}
    };
    world.collisionBoxes[0] = aabb_create((vector_float3){0, -10, 0}, (vector_float3){20, 0.25, 20});

    // Ceiling (y = 10)
    world.meshes[1] = (WorldMesh) {
        .mesh = create_cube_mesh(device, (vector_float3){40, 0.5, 40}, vertexDescriptor),
        .position = (vector_float3){0, 10, 0},
        .scale = (vector_float3){1, 1, 1}
    };
    world.collisionBoxes[1] = aabb_create((vector_float3){0, 10, 0}, (vector_float3){20, 0.25, 20});

    // Front wall (z = -20)
    world.meshes[2] = (WorldMesh) {
        .mesh = create_cube_mesh(device, (vector_float3){40, 20, 0.5}, vertexDescriptor),
        .position = (vector_float3){0, 0, -20},
        .scale = (vector_float3){1, 1, 1}
    };
    world.collisionBoxes[2] = aabb_create((vector_float3){0, 0, -20}, (vector_float3){20, 10, 0.25});

    // Back wall (z = 20)
    world.meshes[3] = (WorldMesh) {
        .mesh = create_cube_mesh(device, (vector_float3){40, 20, 0.5}, vertexDescriptor),
        .position = (vector_float3){0, 0, 20},
        .scale = (vector_float3){1, 1, 1}
    };
    world.collisionBoxes[3] = aabb_create((vector_float3){0, 0, 20}, (vector_float3){20, 10, 0.25});

    // Left wall (x = -20)
    world.meshes[4] = (WorldMesh) {
        .mesh = create_cube_mesh(device, (vector_float3){0.5, 20, 40}, vertexDescriptor),
        .position = (vector_float3){-20, 0, 0},
        .scale = (vector_float3){1, 1, 1}
    };
    world.collisionBoxes[4] = aabb_create((vector_float3){-20, 0, 0}, (vector_float3){0.25, 10, 20});

    // Right wall (x = 20)
    world.meshes[5] = (WorldMesh) {
        .mesh = create_cube_mesh(device, (vector_float3){0.5, 20, 40}, vertexDescriptor),
        .position = (vector_float3){20, 0, 0},
        .scale = (vector_float3){1, 1, 1}
    };
    world.collisionBoxes[5] = aabb_create((vector_float3){20, 0, 0}, (vector_float3){0.25, 10, 20});

    // Test cube (visible mesh and collision box)
    world.meshes[6] = (WorldMesh) {
        .mesh = create_cube_mesh(device, (vector_float3){2, 2, 2}, vertexDescriptor),
        .position = (vector_float3){5, -7, -10},
        .scale = (vector_float3){1, 1, 1}
    };
    world.collisionBoxes[6] = aabb_create((vector_float3){5, -7, -10}, (vector_float3){1, 1, 1});

    return world;
}

void world_release(World *world)
{
    if (world->meshes) {
        free(world->meshes);
        world->meshes = NULL;
    }
    world->meshCount = 0;

    if (world->collisionBoxes) {
        free(world->collisionBoxes);
        world->collisionBoxes = NULL;
    }
    world->collisionBoxCount = 0;
}

AABB* world_get_collision_boxes(World *world, NSUInteger *outCount)
{
    if (outCount) {
        *outCount = world->collisionBoxCount;
    }
    return world->collisionBoxes;
}
