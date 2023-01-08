#include "screen_renderer.hpp"

#include <stdio.h>
#include <stdlib.h>

ScreenRenderer::ScreenRenderer() {
    dpy = XOpenDisplay(NULL);

    if (dpy == NULL) {
        printf("Cannot connect to X server.\n");
        exit(0);
    }

    Window root = DefaultRootWindow(dpy);

    GLint att[] = {GLX_RGBA, GLX_DEPTH_SIZE, 24, GLX_DOUBLEBUFFER, None};
    XVisualInfo *vi = glXChooseVisual(dpy, 0, att);

    if (vi == NULL) {
        printf("No appropriate visual found.\n");
        exit(0);
    }

    Colormap cmap = XCreateColormap(dpy, root, vi->visual, AllocNone);

    XSetWindowAttributes swa;
    swa.colormap = cmap;
    swa.event_mask = ExposureMask | KeyPressMask;

    win = XCreateWindow(dpy, root, 0, 0, 256 * 4, 240 * 4, 0, vi->depth, InputOutput, vi->visual, CWColormap | CWEventMask, &swa);

    XMapWindow(dpy, win);
    XStoreName(dpy, win, "PPU output");

    glc = glXCreateContext(dpy, vi, NULL, GL_TRUE);
    glXMakeCurrent(dpy, win, glc);

    glGenTextures(1, &tex);
    glEnable(GL_TEXTURE_2D);
    glBindTexture(GL_TEXTURE_2D, tex);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE,GL_MODULATE);
    glDisable(GL_TEXTURE_2D);
}

ScreenRenderer::~ScreenRenderer() {
    glDeleteTextures(1, &tex);
    glXMakeCurrent(dpy, None, NULL);
    glXDestroyContext(dpy, glc);
    XDestroyWindow(dpy, win);
    XCloseDisplay(dpy);
}

void ScreenRenderer::updateScreen(GLubyte pixels[240][256][3]) {
    XWindowAttributes gwa;
    XGetWindowAttributes(dpy, win, &gwa);
    glViewport(0, 0, gwa.width, gwa.height);

    glClear(GL_COLOR_BUFFER_BIT);
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_CULL_FACE);
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();

    // bind texture
    glEnable(GL_TEXTURE_2D);
    glBindTexture(GL_TEXTURE_2D, tex);
    
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB8, 256, 240, 0, GL_RGB, GL_UNSIGNED_BYTE, pixels);

    glBegin(GL_QUADS);
        glTexCoord2f(0.0, 0.0); glVertex2f(-1.0,  1.0);
        glTexCoord2f(1.0, 0.0); glVertex2f( 1.0,  1.0);
        glTexCoord2f(1.0, 1.0); glVertex2f( 1.0, -1.0);
        glTexCoord2f(0.0, 1.0); glVertex2f(-1.0, -1.0);
    glEnd();

    glBindTexture(GL_TEXTURE_2D, 0);
    glDisable(GL_TEXTURE_2D);

    glFlush();

    glXSwapBuffers(dpy, win);
}
