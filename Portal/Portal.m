//
//  Portal.m
//  Portal
//
//  Created by Oliver Steiner on 22.01.2026.
//

#import <Foundation/Foundation.h>
#import <simd/simd.h>
#import "Portal.h"

Portal portal_create(PortalColor color, vector_float3 position, vector_float3 normal)
{
    // Normalize the normal vector
    normal = simd_normalize(normal);

    // Calculate up and right vectors for portal orientation
    // Choose a world up vector that's not parallel to the normal
    vector_float3 worldUp = (vector_float3){0, 1, 0};
    if (fabsf(simd_dot(normal, worldUp)) > 0.99f) {
        worldUp = (vector_float3){1, 0, 0}; // Use right vector if normal is vertical
    }

    vector_float3 right = simd_normalize(simd_cross(worldUp, normal));
    vector_float3 up = simd_normalize(simd_cross(normal, right));

    Portal portal = {
        .active = YES,
        .color = color,
        .position = position,
        .normal = normal,
        .up = up,
        .right = right,
        .width = 2.0f,
        .height = 3.0f,
        .transform = matrix_identity_float4x4,
        .boundingBox = aabb_create(position, (vector_float3){1.0f, 1.5f, 0.1f})
    };

    portal_update_transform(&portal);

    return portal;
}

void portal_deactivate(Portal *portal)
{
    portal->active = NO;
}

BOOL portal_is_active(Portal *portal)
{
    return portal->active;
}

matrix_float4x4 portal_calculate_transform(vector_float3 position, vector_float3 normal, vector_float3 up)
{
    // Create transformation matrix for portal
    // Portal faces in the direction of -normal (so objects come OUT of the portal)
    vector_float3 forward = -normal;
    vector_float3 right = simd_normalize(simd_cross(up, forward));
    up = simd_normalize(simd_cross(forward, right));

    matrix_float4x4 transform = {
        .columns[0] = {right.x, right.y, right.z, 0},
        .columns[1] = {up.x, up.y, up.z, 0},
        .columns[2] = {forward.x, forward.y, forward.z, 0},
        .columns[3] = {position.x, position.y, position.z, 1}
    };

    return transform;
}

vector_float3 portal_get_forward(Portal *portal)
{
    // Portal forward is the negative normal (direction things exit)
    return -portal->normal;
}

BOOL portal_contains_point(Portal *portal, vector_float3 point)
{
    if (!portal->active) return NO;

    // Transform point to portal local space
    vector_float3 localPoint = point - portal->position;

    // Project onto portal plane
    float distanceToPlane = simd_dot(localPoint, portal->normal);
    if (fabsf(distanceToPlane) > 0.1f) return NO; // Too far from portal plane

    // Check if within portal bounds
    float rightDist = fabsf(simd_dot(localPoint, portal->right));
    float upDist = fabsf(simd_dot(localPoint, portal->up));

    return (rightDist <= portal->width * 0.5f && upDist <= portal->height * 0.5f);
}

PortalPair portal_pair_create(void)
{
    PortalPair pair = {
        .blue = {.active = NO, .color = PortalColorBlue},
        .orange = {.active = NO, .color = PortalColorOrange},
        .linked = NO
    };
    return pair;
}

void portal_pair_place(PortalPair *pair, PortalColor color, vector_float3 position, vector_float3 normal)
{
    if (color == PortalColorBlue) {
        pair->blue = portal_create(PortalColorBlue, position, normal);
    } else {
        pair->orange = portal_create(PortalColorOrange, position, normal);
    }

    // Update linked status
    pair->linked = pair->blue.active && pair->orange.active;
}

BOOL portal_pair_is_linked(PortalPair *pair)
{
    return pair->linked && pair->blue.active && pair->orange.active;
}

Portal* portal_pair_get_destination(PortalPair *pair, PortalColor sourceColor)
{
    if (!portal_pair_is_linked(pair)) return NULL;

    return (sourceColor == PortalColorBlue) ? &pair->orange : &pair->blue;
}

vector_float3 portal_calculate_exit_position(Portal *entry, Portal *exit, vector_float3 entryPosition, vector_float3 *velocity)
{
    if (!entry->active || !exit->active) return entryPosition;

    // Calculate position relative to entry portal (in entry portal's local space)
    vector_float3 relativePos = entryPosition - entry->position;

    // Decompose into portal local coordinates
    float rightOffset = simd_dot(relativePos, entry->right);
    float upOffset = simd_dot(relativePos, entry->up);
    float forwardOffset = simd_dot(relativePos, entry->normal);

    // Transform to exit portal's local space (with 180° rotation)
    // When you enter a portal, you come out facing the opposite direction
    vector_float3 exitPosition = exit->position;
    exitPosition = exitPosition - (exit->right * rightOffset);  // Flip horizontal
    exitPosition = exitPosition + (exit->up * upOffset);
    exitPosition = exitPosition - (exit->normal * forwardOffset); // Exit in front of portal

    // Transform velocity
    if (velocity) {
        // Decompose velocity into entry portal space
        float velRight = simd_dot(*velocity, entry->right);
        float velUp = simd_dot(*velocity, entry->up);
        float velForward = simd_dot(*velocity, entry->normal);

        // Transform to exit portal space (with flip)
        *velocity = (exit->right * -velRight) +
                    (exit->up * velUp) +
                    (exit->normal * -velForward);
    }

    return exitPosition;
}

void portal_calculate_exit_rotation(Portal *entry, Portal *exit, float *pitch, float *yaw)
{
    if (!entry->active || !exit->active || !pitch || !yaw) return;

    // Calculate camera forward vector from current pitch/yaw
    float cosPitch = cosf(*pitch);
    float sinPitch = sinf(*pitch);
    float cosYaw = cosf(*yaw);
    float sinYaw = sinf(*yaw);

    vector_float3 cameraForward = (vector_float3){
        sinYaw * cosPitch,
        sinPitch,
        -cosYaw * cosPitch
    };

    // Transform camera forward through portals
    // Decompose into entry portal space
    float fwdRight = simd_dot(cameraForward, entry->right);
    float fwdUp = simd_dot(cameraForward, entry->up);
    float fwdForward = simd_dot(cameraForward, entry->normal);

    // Transform to exit portal space (with 180° rotation)
    vector_float3 newForward = (exit->right * -fwdRight) +
                               (exit->up * fwdUp) +
                               (exit->normal * -fwdForward);

    newForward = simd_normalize(newForward);

    // Convert back to pitch/yaw
    *pitch = asinf(newForward.y);
    *yaw = atan2f(newForward.x, -newForward.z);
}

void portal_update_transform(Portal *portal)
{
    portal->transform = portal_calculate_transform(portal->position, portal->normal, portal->up);

    // Update bounding box
    portal->boundingBox = aabb_create(portal->position,
                                     (vector_float3){portal->width * 0.5f,
                                                    portal->height * 0.5f,
                                                    0.2f});
}
