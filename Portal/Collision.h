//
//  Collision.h
//  Portal
//
//  Created by Oliver Steiner on 22.01.2026.
//

#ifndef Collision_h
#define Collision_h

#import <simd/simd.h>
#import <Foundation/Foundation.h>

// Axis-Aligned Bounding Box
typedef struct {
    vector_float3 min;  // Minimum corner (x, y, z)
    vector_float3 max;  // Maximum corner (x, y, z)
} AABB;

// Collision result information
typedef struct {
    BOOL collided;
    vector_float3 normal;      // Surface normal at collision point
    float penetrationDepth;    // How far into the object we penetrated
    vector_float3 contactPoint; // Point of contact
} CollisionResult;

// Create an AABB from center position and half extents
AABB aabb_create(vector_float3 center, vector_float3 halfExtents);

// Create an AABB from min and max corners
AABB aabb_from_min_max(vector_float3 min, vector_float3 max);

// Check if a point is inside an AABB
BOOL aabb_contains_point(AABB box, vector_float3 point);

// Check if two AABBs intersect
BOOL aabb_intersects_aabb(AABB a, AABB b);

// Test collision between moving AABB and static AABB
// Returns collision result with normal and penetration depth
CollisionResult aabb_sweep_test(AABB moving, vector_float3 velocity, AABB stationary);

// Resolve collision by moving the AABB out of penetration
// Returns the corrected position
vector_float3 aabb_resolve_collision(AABB moving, AABB stationary, CollisionResult collision);

// Get the closest point on an AABB to a given point
vector_float3 aabb_closest_point(AABB box, vector_float3 point);

// Expand an AABB by a given amount on all sides
AABB aabb_expand(AABB box, float amount);

// Get AABB center point
vector_float3 aabb_center(AABB box);

// Get AABB dimensions (width, height, depth)
vector_float3 aabb_size(AABB box);

// Helper: Create player AABB from camera position
// Player is a capsule approximated as AABB with radius and height
AABB aabb_create_player(vector_float3 cameraPosition, float radius, float height);

#endif /* Collision_h */