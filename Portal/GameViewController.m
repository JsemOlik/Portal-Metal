//
//  GameViewController.m
//  Portal
//
//  Created by Oliver Steiner on 22.01.2026.
//

#import "GameViewController.h"
#import "Renderer.h"

@implementation GameViewController
{
    MTKView *_view;

    Renderer *_renderer;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    _view = (MTKView *)self.view;

    _view.device = MTLCreateSystemDefaultDevice();

    if(!_view.device || ![_view.device supportsFamily:MTLGPUFamilyMetal4])
    {
        NSLog(@"Metal 4 is not supported on this device");
        self.view = [[NSView alloc] initWithFrame:self.view.frame];
        return;
    }

    _renderer = [[Renderer alloc] initWithMetalKitView:_view];

    [_renderer mtkView:_view drawableSizeWillChange:_view.drawableSize];

    _view.delegate = _renderer;
    
    // Enable key and mouse event tracking
    [self.view setAcceptsTouchEvents:YES];
}

- (void)keyDown:(NSEvent *)event
{
    [_renderer handleKeyDown:event];
}

- (void)keyUp:(NSEvent *)event
{
    [_renderer handleKeyUp:event];
}

- (void)mouseMoved:(NSEvent *)event
{
    [_renderer handleMouseMove:event];
}

@end
