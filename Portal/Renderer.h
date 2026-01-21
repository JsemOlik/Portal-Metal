//
//  Renderer.h
//  Portal
//
//  Created by Oliver Steiner on 22.01.2026.
//

#import <MetalKit/MetalKit.h>
#import "Player.h"
#import "World.h"

// Our platform independent renderer class.   Implements the MTKViewDelegate protocol which
//   allows it to accept per-frame update and drawable resize callbacks.
@interface Renderer : NSObject <MTKViewDelegate>

-(nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)view;
- (void)handleKeyDown:(NSEvent *)event;
- (void)handleKeyUp:(NSEvent *)event;
- (void)handleMouseMove:(NSEvent *)event;

@end

