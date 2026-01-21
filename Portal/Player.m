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
        .gravity = -20.0f,
        .radius = 0.4f,
        .height = 1.8f
    };
}

AABB player_get_collision_box(Player *player)
{
    return aabb_create_player(player->camera.position, player->radius, player->height);
}

void player_update(Player *player, float deltaTime, float moveInput[3], float mouseDelta[2], AABB *collisionBoxes, NSUInteger collisionBoxCount)
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

    // Calculate desired new position
    vector_float3 desiredPosition = player->camera.position + (player->velocity * deltaTime);

    // Create player collision box at desired position
    Player testPlayer = *player;
    testPlayer.camera.position = desiredPosition;
    AABB playerBox = player_get_collision_box(&testPlayer);

    // Test against all collision boxes and resolve
    vector_float3 finalPosition = desiredPosition;
    BOOL hadCollision = NO;

    for (NSUInteger i = 0; i < collisionBoxCount; i++) {
        AABB obstacle = collisionBoxes[i];
        CollisionResult collision = aabb_sweep_test(playerBox, player->velocity, obstacle);

        if (collision.collided) {
            hadCollision = YES;

            // Resolve collision by moving player out of obstacle
            vector_float3 correctedCenter = aabb_resolve_collision(playerBox, obstacle, collision);

            // Convert center back to camera position (center is at feet + height/2)
            finalPosition = correctedCenter;
            finalPosition.y += player->height * 0.5f; // Convert from center to eye level

            // Slide along the collision surface
            // Remove velocity component in the direction of the normal
            float velocityDotNormal = simd_dot(player->velocity, collision.normal);
            if (velocityDotNormal < 0) {
                player->velocity = player->velocity - (collision.normal * velocityDotNormal);
            }

            // Update player box for next collision test
            testPlayer.camera.position = finalPosition;
            playerBox = player_get_collision_box(&testPlayer);
        }
    }

    player->camera.position = finalPosition;

    // Check if on ground (feet touching floor)
    float playerFootY = player->camera.position.y - player->height;
    float groundY = -9.75f;

    if (fabsf(playerFootY - groundY) < 0.01f || playerFootY < groundY) {
        player->camera.position.y = groundY + player->height;
        if (player->velocity.y < 0) {
            player->velocity.y = 0;
        }
        player->onGround = YES;
    } else {
        player->onGround = NO;
    }
}

void player_apply_gravity(Player *player, float deltaTime)
{
    player->velocity.y += player->gravity * deltaTime;
}
