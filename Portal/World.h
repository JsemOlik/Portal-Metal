//
//  World.h
//  Portal
//
//  Created by Oliver Steiner on 22.01.2026.
//

#ifndef World_h
#define World_h

#import <MetalKit/MetalKit.h>

typedef struct {
    MTKMesh *mesh;
    vector_float3 position;
    vector_float3 scale;
} WorldMesh;

typedef struct {
    WorldMesh *meshes;
    NSUInteger meshCount;
} World;

World world_create(id<MTLDevice> device, MTLVertexDescriptor *vertexDescriptor);
void world_release(World *world);

#endif /* World_h */
