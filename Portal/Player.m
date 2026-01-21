//
//  Player.m
//  Portal
//
//  Created by Oliver Steiner on 22.01.2026.
//

#import <Foundation/Foundation.h>
#import <simd/simd.h>
#import "Player.h"

Player player_create(vector_float3 startPosition)
{
    return (Player) {
        .camera = camera_create(startPosition),
        .velocity = (vector_float3){0, 0, 0},
        .moveSpeed = 5.0f,
        .mouseSensitivity = 0.002f,
        .onGround = YES,
        .gravity = -20.0f
    };
}

void player_update(Player *player, float deltaTime, float moveInput[3], float mouseDelta[2])
{
    // Update camera rotation from mouse
    player->camera.yaw += mouseDelta[0] * player->mouseSensitivity;
    player->camera.pitch += mouseDelta[1] * player->mouseSensitivity;

    // Clamp pitch to prevent flipping
    if (player->camera.pitch > M_PI_2 - 0.1f) {
        player->camera.pitch = M_PI_2 - 0.1f;
    }
    if (player->camera.pitch < -M_PI_2 + 0.1f) {
        player->camera.pitch = -M_PI_2 + 0.1f;
    }

    // Calculate movement direction
    vector_float3 forward = camera_forward(player->camera);
    vector_float3 right = camera_right(player->camera);

    // Zero out vertical component of forward for ground movement
    forward.y = 0;
    forward = simd_normalize(forward);

    vector_float3 moveDir = (vector_float3){0, 0, 0};
    moveDir = moveDir + (forward * moveInput[2]); // forward/back
    moveDir = moveDir + (right * moveInput[0]);   // left/right

    if (simd_length(moveDir) > 0) {
        moveDir = simd_normalize(moveDir);
    }

    // Apply movement
    vector_float3 moveVelocity = moveDir * player->moveSpeed;
    moveVelocity.y = player->velocity.y; // preserve vertical velocity
    player->velocity = moveVelocity;

    // Apply gravity
    player_apply_gravity(player, deltaTime);

    // Update position
    player->camera.position = player->camera.position + (player->velocity * deltaTime);

    // Ground collision - floor mesh is at y=-10 with height 0.5
    // So top surface is at y = -10 + 0.25 = -9.75
    float groundY = -9.75f;
    float playerHeight = 1.8f; // Player eye height
    float playerFootY = player->camera.position.y - playerHeight;

    if (playerFootY <= groundY) {
        player->camera.position.y = groundY + playerHeight;
        player->velocity.y = 0;
        player->onGround = YES;
    } else {
        player->onGround = NO;
    }
}

void player_apply_gravity(Player *player, float deltaTime)
{
    player->velocity.y += player->gravity * deltaTime;
}
