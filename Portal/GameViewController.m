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
}

- (void)viewDidAppear
{
    [super viewDidAppear];

    // Make this view controller the first responder to receive keyboard events
    [self.view.window makeFirstResponder:self];

    // Enable mouse moved events for the window
    [self.view.window setAcceptsMouseMovedEvents:YES];


}

- (BOOL)acceptsFirstResponder
{
    return YES;
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

- (void)mouseDragged:(NSEvent *)event
{
    [_renderer handleMouseMove:event];
}

- (void)mouseDown:(NSEvent *)event
{
    // Left click - shoot blue portal
    [_renderer handleMouseClick:event isRightClick:NO];

    // Also ensure window has focus
    [self.view.window makeFirstResponder:self];
}

- (void)rightMouseDown:(NSEvent *)event
{
    // Right click - shoot orange portal
    [_renderer handleMouseClick:event isRightClick:YES];
}

- (BOOL)resignFirstResponder
{
    // Clear all key states when losing focus to prevent sticking
    [_renderer handleFocusLost];
    return [super resignFirstResponder];
}

@end
