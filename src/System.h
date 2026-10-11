/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

// The few system declarations Dared Slugger needs. They are written out
// here, rather than taken from SDK headers, so that the game builds with
// nothing but a compiler, a linker and stub libraries for the frameworks it
// links against.

#ifndef SYSTEM_H
#define SYSTEM_H

// Objective-C runtime and basic types

typedef signed char BOOL;
#define YES ((BOOL)1)
#define NO ((BOOL)0)
#define nil ((id)0)

typedef unsigned int NSUInteger;
typedef int NSInteger;
typedef double NSTimeInterval;

// Core Graphics

typedef float CGFloat;

typedef struct {
  CGFloat x;
  CGFloat y;
} CGPoint;

typedef struct {
  CGFloat width;
  CGFloat height;
} CGSize;

typedef struct {
  CGPoint origin;
  CGSize size;
} CGRect;

typedef struct CGContext *CGContextRef;
typedef struct CGColorSpace *CGColorSpaceRef;

#define kCGImageAlphaPremultipliedLast 1

CGColorSpaceRef CGColorSpaceCreateDeviceRGB(void);
void CGColorSpaceRelease(CGColorSpaceRef space);
CGContextRef CGBitmapContextCreate(void *data, unsigned int width,
                                   unsigned int height,
                                   unsigned int bitsPerComponent,
                                   unsigned int bytesPerRow,
                                   CGColorSpaceRef space,
                                   unsigned int bitmapInfo);
void CGContextRelease(CGContextRef context);
void CGContextTranslateCTM(CGContextRef context, CGFloat tx, CGFloat ty);
void CGContextScaleCTM(CGContextRef context, CGFloat sx, CGFloat sy);
void CGContextSetRGBFillColor(CGContextRef context, CGFloat red, CGFloat green,
                              CGFloat blue, CGFloat alpha);

// C library

long time(long *out);
unsigned long long mach_absolute_time(void);
float sinf(float x);
float cosf(float x);
float sqrtf(float x);
void *calloc(unsigned long count, unsigned long size);
void free(void *pointer);

// Foundation

@interface NSObject {
  Class isa;
}
+ (Class)class;
+ (instancetype)alloc;
- (instancetype)init;
- (void)release;
- (void)dealloc;
@end

@interface NSAutoreleasePool : NSObject
- (void)drain;
@end

@interface NSString : NSObject
+ (NSString *)stringWithUTF8String:(const char *)string;
@end

@interface NSData : NSObject
+ (NSData *)dataWithContentsOfFile:(NSString *)path;
- (const void *)bytes;
- (NSUInteger)length;
@end

@interface NSUserDefaults : NSObject
+ (NSUserDefaults *)standardUserDefaults;
- (NSInteger)integerForKey:(NSString *)key;
- (void)setInteger:(NSInteger)value forKey:(NSString *)key;
- (BOOL)synchronize;
@end

@interface NSBundle : NSObject
+ (NSBundle *)mainBundle;
- (NSString *)pathForResource:(NSString *)name ofType:(NSString *)extension;
@end

@interface NSSet : NSObject
- (id)anyObject;
@end

@interface NSTimer : NSObject
+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)interval
                                     target:(id)target
                                   selector:(SEL)selector
                                   userInfo:(id)userInfo
                                    repeats:(BOOL)repeats;
@end

NSString *NSStringFromClass(Class aClass);

// UIKit

@interface UIResponder : NSObject
@end

@interface UIEvent : NSObject
@end

@interface UIFont : NSObject
+ (UIFont *)boldSystemFontOfSize:(CGFloat)size;
@end

// UIStringDrawing
@interface NSString (UIStringDrawing)
- (CGSize)sizeWithFont:(UIFont *)font;
- (CGSize)drawAtPoint:(CGPoint)point withFont:(UIFont *)font;
@end

@interface UIView : UIResponder
- (instancetype)initWithFrame:(CGRect)frame;
- (CGRect)bounds;
- (void)addSubview:(UIView *)view;
- (id)layer;
@end

@interface UITouch : NSObject
- (CGPoint)locationInView:(UIView *)view;
@end

@interface UIWindow : UIView
- (void)makeKeyAndVisible;
@end

@interface UIScreen : NSObject
+ (UIScreen *)mainScreen;
- (CGRect)bounds;
@end

@interface UIApplication : UIResponder
- (void)setStatusBarHidden:(BOOL)hidden;
@end

void UIGraphicsPushContext(CGContextRef context);
void UIGraphicsPopContext(void);
int UIApplicationMain(int argc, char *argv[], NSString *principalClassName,
                      NSString *delegateClassName);

// Core Animation

@interface CALayer : NSObject
- (void)setOpaque:(BOOL)opaque;
@end

@interface CAEAGLLayer : CALayer
@end

// OpenGL ES (EAGL)

typedef enum { kEAGLRenderingAPIOpenGLES1 = 1 } EAGLRenderingAPI;

@interface EAGLContext : NSObject
- (instancetype)initWithAPI:(EAGLRenderingAPI)api;
+ (BOOL)setCurrentContext:(EAGLContext *)context;
- (BOOL)renderbufferStorage:(unsigned int)target fromDrawable:(id)drawable;
- (BOOL)presentRenderbuffer:(unsigned int)target;
@end

// OpenGL ES 1.1, with OES_framebuffer_object

typedef unsigned int GLuint;
typedef unsigned int GLenum;
typedef int GLint;
typedef int GLsizei;
typedef float GLfloat;
typedef unsigned int GLbitfield;

#define GL_ONE 1
#define GL_TRIANGLES 0x0004
#define GL_TRIANGLE_FAN 0x0006
#define GL_SRC_ALPHA 0x0302
#define GL_ONE_MINUS_SRC_ALPHA 0x0303
#define GL_BLEND 0x0BE2
#define GL_TEXTURE_2D 0x0DE1
#define GL_UNSIGNED_BYTE 0x1401
#define GL_FLOAT 0x1406
#define GL_MODELVIEW 0x1700
#define GL_PROJECTION 0x1701
#define GL_RGB 0x1907
#define GL_RGBA 0x1908
#define GL_LINEAR 0x2601
#define GL_TEXTURE_MAG_FILTER 0x2800
#define GL_TEXTURE_MIN_FILTER 0x2801
#define GL_TEXTURE_WRAP_S 0x2802
#define GL_TEXTURE_WRAP_T 0x2803
#define GL_COLOR_BUFFER_BIT 0x4000
#define GL_VERTEX_ARRAY 0x8074
#define GL_TEXTURE_COORD_ARRAY 0x8078
#define GL_CLAMP_TO_EDGE 0x812F
#define GL_FRAMEBUFFER_OES 0x8D40
#define GL_RENDERBUFFER_OES 0x8D41
#define GL_RENDERBUFFER_WIDTH_OES 0x8D42
#define GL_RENDERBUFFER_HEIGHT_OES 0x8D43
#define GL_COLOR_ATTACHMENT0_OES 0x8CE0

void glViewport(GLint x, GLint y, GLsizei width, GLsizei height);
void glClearColor(GLfloat red, GLfloat green, GLfloat blue, GLfloat alpha);
void glClear(GLbitfield mask);
void glMatrixMode(GLenum mode);
void glLoadIdentity(void);
void glOrthof(GLfloat left, GLfloat right, GLfloat bottom, GLfloat top,
              GLfloat zNear, GLfloat zFar);
void glEnable(GLenum cap);
void glDisable(GLenum cap);
void glBlendFunc(GLenum sfactor, GLenum dfactor);
void glEnableClientState(GLenum array);
void glDisableClientState(GLenum array);
void glVertexPointer(GLint size, GLenum type, GLsizei stride,
                     const void *pointer);
void glTexCoordPointer(GLint size, GLenum type, GLsizei stride,
                       const void *pointer);
void glGenTextures(GLsizei n, GLuint *textures);
void glBindTexture(GLenum target, GLuint texture);
void glTexParameteri(GLenum target, GLenum pname, GLint param);
void glTexImage2D(GLenum target, GLint level, GLint internalformat,
                  GLsizei width, GLsizei height, GLint border, GLenum format,
                  GLenum type, const void *pixels);
void glColor4f(GLfloat red, GLfloat green, GLfloat blue, GLfloat alpha);
void glDrawArrays(GLenum mode, GLint first, GLsizei count);
void glGenFramebuffersOES(GLsizei n, GLuint *framebuffers);
void glBindFramebufferOES(GLenum target, GLuint framebuffer);
void glGenRenderbuffersOES(GLsizei n, GLuint *renderbuffers);
void glBindRenderbufferOES(GLenum target, GLuint renderbuffer);
void glFramebufferRenderbufferOES(GLenum target, GLenum attachment,
                                  GLenum renderbuffertarget,
                                  GLuint renderbuffer);
void glGetRenderbufferParameterivOES(GLenum target, GLenum pname,
                                     GLint *params);

// OpenAL

typedef struct ALCdevice_struct ALCdevice;
typedef struct ALCcontext_struct ALCcontext;
typedef char ALCboolean;
typedef char ALCchar;
typedef int ALCint;
typedef unsigned int ALuint;
typedef int ALint;
typedef int ALsizei;
typedef int ALenum;

#define AL_NO_ERROR 0
#define AL_BUFFER 0x1009
#define AL_FORMAT_MONO16 0x1101

ALCdevice *alcOpenDevice(const ALCchar *deviceName);
ALCcontext *alcCreateContext(ALCdevice *device, const ALCint *attributes);
ALCboolean alcMakeContextCurrent(ALCcontext *context);
void alGenBuffers(ALsizei count, ALuint *buffers);
void alBufferData(ALuint buffer, ALenum format, const void *data, ALsizei size,
                  ALsizei frequency);
void alGenSources(ALsizei count, ALuint *sources);
void alSourcei(ALuint source, ALenum parameter, ALint value);
void alSourcePlay(ALuint source);
ALenum alGetError(void);

#endif
