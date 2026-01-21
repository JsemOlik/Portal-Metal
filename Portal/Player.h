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

typedef struct {
    Camera camera;
    vector_float3 velocity;
    float moveSpeed;
    float mouseSensitivity;
    BOOL onGround;
    float gravity;
} Player;

Player player_create(vector_float3 startPosition);
void player_update(Player *player, float deltaTime, float moveInput[3], float mouseDelta[2]);
void player_apply_gravity(Player *player, float deltaTime);

#endif /* Player_h */
