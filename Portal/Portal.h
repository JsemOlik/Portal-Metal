//
//  Portal.h
//  Portal
//
//  Created by Oliver Steiner on 22.01.2026.
//

#ifndef Portal_h
#define Portal_h

#import <Foundation/Foundation.h>
#import <simd/simd.h>
#import <MetalKit/MetalKit.h>
#import "Collision.h"

// Portal colors
typedef enum {
    PortalColorBlue = 0,
    PortalColorOrange = 1
} PortalColor;

// Portal state
typedef struct {
    BOOL active;                    // Is this portal placed?
    PortalColor color;              // Blue or Orange
    vector_float3 position;         // Portal center position
    vector_float3 normal;           // Surface normal (direction portal faces)
    vector_float3 up;               // Up direction for portal orientation
    vector_float3 right;            // Right direction for portal orientation
    float width;                    // Portal width (default 2.0)
    float height;                   // Portal height (default 3.0)
    matrix_float4x4 transform;      // Full transformation matrix
    AABB boundingBox;               // Collision box for portal
} Portal;

// Portal pair (blue and orange linked together)
typedef struct {
    Portal blue;
    Portal orange;
    BOOL linked;                    // Are both portals active and linked?
} PortalPair;

// Create a new portal at a position with a surface normal
Portal portal_create(PortalColor color, vector_float3 position, vector_float3 normal);

// Deactivate a portal
void portal_deactivate(Portal *portal);

// Check if a portal is active
BOOL portal_is_active(Portal *portal);

// Calculate portal transformation matrix from position and normal
matrix_float4x4 portal_calculate_transform(vector_float3 position, vector_float3 normal, vector_float3 up);

// Get the portal's forward direction (direction player exits)
vector_float3 portal_get_forward(Portal *portal);

// Check if a point is within the portal's bounds
BOOL portal_contains_point(Portal *portal, vector_float3 point);

// Create a portal pair
PortalPair portal_pair_create(void);

// Place a portal in the pair
void portal_pair_place(PortalPair *pair, PortalColor color, vector_float3 position, vector_float3 normal);

// Check if both portals are active and linked
BOOL portal_pair_is_linked(PortalPair *pair);

// Get the destination portal for a given portal color
Portal* portal_pair_get_destination(PortalPair *pair, PortalColor sourceColor);

// Calculate exit position and velocity when entering a portal
// Returns the new position and modifies the velocity vector
vector_float3 portal_calculate_exit_position(Portal *entry, Portal *exit, vector_float3 entryPosition, vector_float3 *velocity);

// Calculate exit rotation (camera orientation) when going through portal
void portal_calculate_exit_rotation(Portal *entry, Portal *exit, float *pitch, float *yaw);

// Update portal transformation matrix (call after changing position or normal)
void portal_update_transform(Portal *portal);

#endif /* Portal_h */