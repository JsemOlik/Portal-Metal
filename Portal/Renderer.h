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
- (void)handleKeyDown:(nonnull NSEvent *)event;
- (void)handleKeyUp:(nonnull NSEvent *)event;
- (void)handleMouseMove:(nonnull NSEvent *)event;
- (void)handleMouseClick:(nonnull NSEvent *)event isRightClick:(BOOL)isRightClick;
- (void)handleFocusLost;

@end
