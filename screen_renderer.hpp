#pragma once

#include <GL/gl.h>
#include <GL/glu.h>
#include <GL/glx.h>
#include <X11/X.h>
#include <X11/Xlib.h>

class ScreenRenderer {
public:
    ScreenRenderer();
    ~ScreenRenderer();

    void updateScreen(GLubyte pixels[240][256][3]);
    
    Display *dpy;

private:
    Window win;
    GLXContext glc;
    GLuint tex;
};
