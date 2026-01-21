//
//  World.h
//  Portal
//
//  Created by Oliver Steiner on 22.01.2026.
//

#ifndef World_h
#define World_h

#import <MetalKit/MetalKit.h>
#import "Collision.h"

typedef struct {
    MTKMesh *mesh;
    vector_float3 position;
    vector_float3 scale;
} WorldMesh;

typedef struct {
    WorldMesh *meshes;
    NSUInteger meshCount;
    AABB *collisionBoxes;  // Collision boxes for static geometry
    NSUInteger collisionBoxCount;
} World;

World world_create(id<MTLDevice> device, MTLVertexDescriptor *vertexDescriptor);
void world_release(World *world);

// Get all collision boxes for the world (walls, floor, ceiling, objects)
AABB* world_get_collision_boxes(World *world, NSUInteger *outCount);

#endif /* World_h */
