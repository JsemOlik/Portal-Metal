//
//  Collision.m
//  Portal
//
//  Created by Oliver Steiner on 22.01.2026.
//

#import <Foundation/Foundation.h>
#import <simd/simd.h>
#import "Collision.h"

AABB aabb_create(vector_float3 center, vector_float3 halfExtents)
{
    return (AABB) {
        .min = center - halfExtents,
        .max = center + halfExtents
    };
}

AABB aabb_from_min_max(vector_float3 min, vector_float3 max)
{
    return (AABB) {
        .min = min,
        .max = max
    };
}

BOOL aabb_contains_point(AABB box, vector_float3 point)
{
    return (point.x >= box.min.x && point.x <= box.max.x &&
            point.y >= box.min.y && point.y <= box.max.y &&
            point.z >= box.min.z && point.z <= box.max.z);
}

BOOL aabb_intersects_aabb(AABB a, AABB b)
{
    return (a.min.x <= b.max.x && a.max.x >= b.min.x &&
            a.min.y <= b.max.y && a.max.y >= b.min.y &&
            a.min.z <= b.max.z && a.max.z >= b.min.z);
}

CollisionResult aabb_sweep_test(AABB moving, vector_float3 velocity, AABB stationary)
{
    CollisionResult result = {
        .collided = NO,
        .normal = (vector_float3){0, 0, 0},
        .penetrationDepth = 0.0f,
        .contactPoint = (vector_float3){0, 0, 0}
    };

    // Check if already intersecting
    if (!aabb_intersects_aabb(moving, stationary)) {
        return result;
    }

    result.collided = YES;

    // Calculate overlap on each axis
    float overlapX = fminf(moving.max.x - stationary.min.x, stationary.max.x - moving.min.x);
    float overlapY = fminf(moving.max.y - stationary.min.y, stationary.max.y - moving.min.y);
    float overlapZ = fminf(moving.max.z - stationary.min.z, stationary.max.z - moving.min.z);

    // Find minimum overlap axis - this is the collision normal direction
    if (overlapX < overlapY && overlapX < overlapZ) {
        // X-axis collision
        result.penetrationDepth = overlapX;
        result.normal = (vector_float3){
            (moving.min.x + moving.max.x) < (stationary.min.x + stationary.max.x) ? -1.0f : 1.0f,
            0, 0
        };
    } else if (overlapY < overlapZ) {
        // Y-axis collision
        result.penetrationDepth = overlapY;
        result.normal = (vector_float3){
            0,
            (moving.min.y + moving.max.y) < (stationary.min.y + stationary.max.y) ? -1.0f : 1.0f,
            0
        };
    } else {
        // Z-axis collision
        result.penetrationDepth = overlapZ;
        result.normal = (vector_float3){
            0, 0,
            (moving.min.z + moving.max.z) < (stationary.min.z + stationary.max.z) ? -1.0f : 1.0f
        };
    }

    // Calculate contact point (center of overlap region)
    vector_float3 overlapMin = (vector_float3){
        fmaxf(moving.min.x, stationary.min.x),
        fmaxf(moving.min.y, stationary.min.y),
        fmaxf(moving.min.z, stationary.min.z)
    };
    vector_float3 overlapMax = (vector_float3){
        fminf(moving.max.x, stationary.max.x),
        fminf(moving.max.y, stationary.max.y),
        fminf(moving.max.z, stationary.max.z)
    };
    result.contactPoint = (overlapMin + overlapMax) * 0.5f;

    return result;
}

vector_float3 aabb_resolve_collision(AABB moving, AABB stationary, CollisionResult collision)
{
    if (!collision.collided) {
        return aabb_center(moving);
    }

    // Move the center out by the penetration depth along the normal
    vector_float3 center = aabb_center(moving);
    vector_float3 correction = collision.normal * collision.penetrationDepth;
    return center + correction;
}

vector_float3 aabb_closest_point(AABB box, vector_float3 point)
{
    vector_float3 closest;
    closest.x = fmaxf(box.min.x, fminf(point.x, box.max.x));
    closest.y = fmaxf(box.min.y, fminf(point.y, box.max.y));
    closest.z = fmaxf(box.min.z, fminf(point.z, box.max.z));
    return closest;
}

AABB aabb_expand(AABB box, float amount)
{
    vector_float3 expansion = (vector_float3){amount, amount, amount};
    return (AABB) {
        .min = box.min - expansion,
        .max = box.max + expansion
    };
}

vector_float3 aabb_center(AABB box)
{
    return (box.min + box.max) * 0.5f;
}

vector_float3 aabb_size(AABB box)
{
    return box.max - box.min;
}

AABB aabb_create_player(vector_float3 cameraPosition, float radius, float height)
{
    // Player is a cylinder approximated as AABB
    // Camera is at eye level, so feet are at cameraPosition.y - height
    vector_float3 feetPosition = cameraPosition;
    feetPosition.y -= height;

    // Create AABB centered at middle of player (between feet and eyes)
    vector_float3 center = feetPosition;
    center.y += height * 0.5f;

    vector_float3 halfExtents = (vector_float3){
        radius,
        height * 0.5f,
        radius
    };

    return aabb_create(center, halfExtents);
}
