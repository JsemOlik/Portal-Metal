//
//  Player.h
//  Portal
//
//  Created by Oliver Steiner on 22.01.2026.
//

#ifndef Player_h
#define Player_h

#import <Foundation/Foundation.h>
#import <simd/simd.h>
#import "Camera.h"
#import "Collision.h"

typedef struct {
    Camera camera;
    vector_float3 velocity;
    float moveSpeed;
    float mouseSensitivity;
    BOOL onGround;
    float gravity;
    float radius;       // Player collision radius
    float height;       // Player height (eye level)
} Player;

Player player_create(vector_float3 startPosition);
void player_update(Player *player, float deltaTime, float moveInput[3], float mouseDelta[2], AABB *collisionBoxes, NSUInteger collisionBoxCount);
void player_apply_gravity(Player *player, float deltaTime);
AABB player_get_collision_box(Player *player);

#endif /* Player_h */
