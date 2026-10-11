/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

// A batter at home plate and a pitcher on the mound, all drawn with OpenGL ES
// 1.1. The pitcher throws, and tapping the screen swings. The yellow zone
// over the plate is where the ball can be hit. Tapping when the ball crosses
// home plate is perfect timing, always a home run. Slightly
// early or late (the brighter band) is a home run half the time, and anywhere
// else in the zone one time in ten. Anything else is a miss. Every pitch
// uses up one of the game's 20 swings, whether it's swung at or not.

#include "BaseballView.h"
#include "Sound.h"
#include "System.h"

// Timing, in ticks before or after the ball crosses home plate.
#define ZONE 7.0f     // How early or late the ball can be hit.
#define SLIGHT 3.5f   // Slightly early or late: 50% home runs.
#define PERFECT 1.5f  // Perfect timing: always a home run.
#define WINDUP_ARM_TICKS 30 // The end of the windup, lifting the leg.
#define ZONE_HALF_WIDTH 22.0f // At the plate, in points.
#define CIRCLE_SEGMENTS 24
// How much further away the ball is when it's pitched than when it crosses
// home plate, from the widths of the rubber and the plate in the picture.
#define PITCH_DEPTH 2.72f
#define BALL_RADIUS 6.0f // At the plate. Bigger than real, to be easy to see.
// The size of the picture that resources/field.rgb was made from, which
// positions on the field are measured in. It's scaled to fill the screen.
#define PICTURE_WIDTH 1024.0f
#define PICTURE_HEIGHT 1536.0f
// The field picture, resources/field.rgb: 8-bit RGB, top row first.
#define FIELD_WIDTH 320
#define FIELD_HEIGHT 480
#define FIELD_TEXTURE_SIZE 512
// The logo on the title screen, resources/logo.rgba: 8-bit RGBA, top row
// first, not premultiplied.
#define LOGO_WIDTH 288
#define LOGO_HEIGHT 96
#define LOGO_TEXTURE_SIZE 512
// The pitcher, resources/pitcher.rgba: 8-bit RGBA, top row first, not
// premultiplied. It's 7 pictures of the pitch, each in a cell
// PITCHER_CELL_WIDTH x PITCHER_CELL_HEIGHT pixels, 4 to a row, at 2 pixels
// a point. The point on the rubber is at the same place in each cell. It's
// loaded into a texture PITCHER_WIDTH square.
#define PITCHER_WIDTH 512
#define PITCHER_HEIGHT 384
#define PITCHER_CELL_WIDTH 128
#define PITCHER_CELL_HEIGHT 192
#define PITCHER_RUBBER_X 64
#define PITCHER_RUBBER_Y 184
// The batter, resources/batter.rgba, likewise: 7 pictures of the swing, from
// the stance to the follow through, in cells BATTER_CELL_WIDTH x
// BATTER_CELL_HEIGHT pixels, with the outside of the planted front foot at
// the same place in each cell. It's loaded into a texture BATTER_WIDTH
// square.
#define BATTER_WIDTH 1024
#define BATTER_HEIGHT 704
#define BATTER_CELL_WIDTH 256
#define BATTER_CELL_HEIGHT 352
#define BATTER_FEET_X 176
#define BATTER_FEET_Y 340
// A game with a home run ends with fireworks behind GAME OVER: a burst every
// BURST_INTERVAL ticks, BURST_COUNT in all, or for as long as the screen shows
// after a new best. Each burst is BURST_SPARKS sparks of one color flying out
// in a ring, falling slowly and fading over BURST_TICKS.
#define BURST_INTERVAL 20
#define BURST_COUNT 8
#define BURST_SPARKS 20
#define BURST_TICKS 50
#define BURST_GRAVITY 0.06f
#define MAX_SPARKS 192
// cos and sin of 360/BURST_SPARKS degrees, to turn each spark's direction
// from the last one's.
#define BURST_COS 0.95105652f
#define BURST_SIN 0.30901699f
#define MAX_VERTS 1024 // Floats in the vertex buffer.
#define TEXT_LENGTH 32 // Longest text, with its terminating 0.
#define TEXT_CACHE_SIZE 16 // Different texts kept as textures.
#define SWINGS_PER_GAME 20
#define BEST_KEY "BestHomeRuns" // Where the best is saved.
#define SOUND_OFF_KEY "SoundOff"  // Saved as 1 when sound is turned off.
#define GAMES_PLAYED_KEY "GamesPlayed"
#define BEST_STREAK_KEY "BestStreak"
#define PERFECT_GAMES_KEY "PerfectGames"

static GLfloat verts[MAX_VERTS];

typedef struct {
  BOOL active;
  CGFloat x, y, dx, dy;
  int ticksLeft;
  int color; // In fireworkColors.
} Spark;

static Spark sparks[MAX_SPARKS];

static const GLfloat fireworkColors[][3] = {
    {0.95f, 0.25f, 0.2f}, {1, 0.6f, 0.15f},   {1, 0.9f, 0.25f},
    {0.35f, 0.9f, 0.35f}, {0.25f, 0.7f, 1},   {0.65f, 0.45f, 1},
    {1, 1, 1},
};
#define FIREWORK_COLORS 7
static GLfloat circleCos[CIRCLE_SEGMENTS + 1];
static GLfloat circleSin[CIRCLE_SEGMENTS + 1];

static NSInteger loadInteger(const char *key) {
  return [[NSUserDefaults standardUserDefaults]
      integerForKey:[NSString stringWithUTF8String:key]];
}

static void saveInteger(const char *key, NSInteger value) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults setInteger:value forKey:[NSString stringWithUTF8String:key]];
  [defaults synchronize];
  [pool drain];
}

// A small xorshift generator. The system's rand() and arc4random() start from
// the same seed every launch in touchHLE, so this is seeded from the clock.
static unsigned int randomState;

static unsigned int nextRandom(void) {
  if (randomState == 0) {
    randomState = (unsigned int)time(0) ^ (unsigned int)mach_absolute_time();
    if (randomState == 0) {
      randomState = 1;
    }
  }
  randomState ^= randomState << 13;
  randomState ^= randomState >> 17;
  randomState ^= randomState << 5;
  return randomState;
}

// A random value from 0 to 1.
static CGFloat randomUnit(void) {
  return (CGFloat)(nextRandom() & 1023) / 1023.0f;
}

static CGFloat absf(CGFloat v) { return v < 0 ? -v : v; }

// Appends a non-negative number to a string, returning the new length.
static int appendNumber(char *text, int length, int number) {
  char digits[10];
  int count = 0;
  do {
    digits[count++] = (char)('0' + number % 10);
    number /= 10;
  } while (number > 0);
  while (count > 0) {
    text[length++] = digits[--count];
  }
  text[length] = 0;
  return length;
}

static int appendText(char *text, int length, const char *more) {
  while (*more) {
    text[length++] = *more++;
  }
  text[length] = 0;
  return length;
}

static void setColor(GLfloat r, GLfloat g, GLfloat b, GLfloat a) {
  glColor4f(r, g, b, a);
}

static void drawFan(int points) {
  glVertexPointer(2, GL_FLOAT, 0, verts);
  glDrawArrays(GL_TRIANGLE_FAN, 0, points);
}

static void fillRect(CGFloat x, CGFloat y, CGFloat w, CGFloat h) {
  verts[0] = x;
  verts[1] = y;
  verts[2] = x + w;
  verts[3] = y;
  verts[4] = x + w;
  verts[5] = y + h;
  verts[6] = x;
  verts[7] = y + h;
  drawFan(4);
}

// A convex quadrilateral, its corners in order.
static void fillQuad(CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2,
                     CGFloat x3, CGFloat y3, CGFloat x4, CGFloat y4) {
  verts[0] = x1;
  verts[1] = y1;
  verts[2] = x2;
  verts[3] = y2;
  verts[4] = x3;
  verts[5] = y3;
  verts[6] = x4;
  verts[7] = y4;
  drawFan(4);
}

static void fillEllipse(CGFloat x, CGFloat y, CGFloat rx, CGFloat ry) {
  verts[0] = x;
  verts[1] = y;
  for (int i = 0; i <= CIRCLE_SEGMENTS; i++) {
    verts[2 + i * 2] = x + circleCos[i] * rx;
    verts[3 + i * 2] = y + circleSin[i] * ry;
  }
  drawFan(CIRCLE_SEGMENTS + 2);
}

static void fillCircle(CGFloat x, CGFloat y, CGFloat radius) {
  fillEllipse(x, y, radius, radius);
}

// A line thickness1 thick at its start, and thickness2 at its end.
static void drawTaperedLine(CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2,
                            CGFloat thickness1, CGFloat thickness2) {
  CGFloat dx = x2 - x1, dy = y2 - y1;
  CGFloat length = sqrtf(dx * dx + dy * dy);
  if (length <= 0) {
    return;
  }
  CGFloat nx = -dy / length * 0.5f, ny = dx / length * 0.5f;
  fillQuad(x1 + nx * thickness1, y1 + ny * thickness1,
           x2 + nx * thickness2, y2 + ny * thickness2,
           x2 - nx * thickness2, y2 - ny * thickness2,
           x1 - nx * thickness1, y1 - ny * thickness1);
}

static void drawLine(CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2,
                     CGFloat thickness) {
  drawTaperedLine(x1, y1, x2, y2, thickness, thickness);
}

// Text is drawn by UIKit, in the bold system font (Liberation Sans Bold in
// touchHLE), into a texture. Each string is drawn once, in white, then kept
// in this cache, and tinted when it's drawn.
typedef struct {
  char text[TEXT_LENGTH];
  CGFloat size;
  GLuint texture; // 0 if not made yet.
  int textureWidth, textureHeight;
  CGFloat width, height; // Of the text.
  int lastUsed;
} TextTexture;

static TextTexture textCache[TEXT_CACHE_SIZE];
static int textClock;

static BOOL sameText(const char *a, const char *b) {
  while (*a && *a == *b) {
    a++;
    b++;
  }
  return *a == *b;
}

static int powerOfTwo(int n) {
  int result = 1;
  while (result < n) {
    result <<= 1;
  }
  return result;
}

static void makeTextTexture(TextTexture *entry, const char *text,
                            CGFloat size) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSString *string = [NSString stringWithUTF8String:text];
  UIFont *font = [UIFont boldSystemFontOfSize:size];
  CGSize textSize = [string sizeWithFont:font];

  int i = 0;
  for (; text[i] && i < TEXT_LENGTH - 1; i++) {
    entry->text[i] = text[i];
  }
  entry->text[i] = 0;
  entry->size = size;
  entry->width = textSize.width;
  entry->height = textSize.height;
  entry->textureWidth = powerOfTwo((int)textSize.width + 1);
  entry->textureHeight = powerOfTwo((int)textSize.height + 1);

  int w = entry->textureWidth, h = entry->textureHeight;
  unsigned char *pixels = calloc(w * h, 4);
  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
  CGContextRef context = CGBitmapContextCreate(
      pixels, w, h, 8, w * 4, colorSpace, kCGImageAlphaPremultipliedLast);
  CGColorSpaceRelease(colorSpace);
  // Flipped, so UIKit draws top down and the first row is the top.
  CGContextTranslateCTM(context, 0, h);
  CGContextScaleCTM(context, 1, -1);
  UIGraphicsPushContext(context);
  CGContextSetRGBFillColor(context, 1, 1, 1, 1);
  CGPoint origin = {0, 0};
  [string drawAtPoint:origin withFont:font];
  UIGraphicsPopContext();
  CGContextRelease(context);

  if (!entry->texture) {
    glGenTextures(1, &entry->texture);
  }
  glBindTexture(GL_TEXTURE_2D, entry->texture);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE,
               pixels);
  free(pixels);
  [pool drain];
}

static TextTexture *textTexture(const char *text, CGFloat size) {
  TextTexture *oldest = &textCache[0];
  for (int i = 0; i < TEXT_CACHE_SIZE; i++) {
    TextTexture *entry = &textCache[i];
    if (entry->texture && entry->size == size && sameText(entry->text, text)) {
      oldest = entry;
      break;
    }
    if (entry->lastUsed < oldest->lastUsed) {
      oldest = entry;
    }
  }
  if (!oldest->texture || oldest->size != size ||
      !sameText(oldest->text, text)) {
    makeTextTexture(oldest, text, size);
  }
  oldest->lastUsed = ++textClock;
  return oldest;
}

static void drawTextTexture(TextTexture *entry, CGFloat x, CGFloat y) {
  GLfloat u = entry->width / entry->textureWidth;
  GLfloat v = entry->height / entry->textureHeight;
  GLfloat texCoords[8] = {0, 0, u, 0, u, v, 0, v};
  glEnable(GL_TEXTURE_2D);
  glBindTexture(GL_TEXTURE_2D, entry->texture);
  glEnableClientState(GL_TEXTURE_COORD_ARRAY);
  glTexCoordPointer(2, GL_FLOAT, 0, texCoords);
  fillRect(x, y, entry->width, entry->height);
  glDisableClientState(GL_TEXTURE_COORD_ARRAY);
  glDisable(GL_TEXTURE_2D);
}

// Text in the bold system font, with a shadow to stand out. Its top is at y,
// and anchor says where x is: 0 for the left edge, 0.5 for the middle.
static void drawTextAnchored(const char *text, CGFloat x, CGFloat y,
                             CGFloat size, CGFloat anchor, GLfloat r,
                             GLfloat g, GLfloat b) {
  TextTexture *entry = textTexture(text, size);
  // Pixel aligned, so the text stays sharp.
  CGFloat left = (int)(x - entry->width * anchor);
  CGFloat top = (int)y;
  // The texture has premultiplied alpha.
  glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
  setColor(0, 0, 0, 0.6f);
  drawTextTexture(entry, left + 2, top + 2);
  setColor(r, g, b, 1);
  drawTextTexture(entry, left, top);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
}

// Text centered on x, with its top at y.
static void drawText(const char *text, CGFloat x, CGFloat y, CGFloat size,
                     GLfloat r, GLfloat g, GLfloat b) {
  drawTextAnchored(text, x, y, size, 0.5f, r, g, b);
}

// Loads a picture from the app's resources, raw pixels with 3 (RGB) or 4
// (RGBA) channels, into the top-left corner of a size x size texture. The
// sides of a texture have to be powers of two.
static GLuint loadTexture(const char *name, const char *type, int w, int h,
                          int channels, int size) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSString *path = [[NSBundle mainBundle]
      pathForResource:[NSString stringWithUTF8String:name]
               ofType:[NSString stringWithUTF8String:type]];
  NSData *data = [NSData dataWithContentsOfFile:path];
  const unsigned char *picture = [data bytes];
  int rowBytes = w * channels;
  unsigned char *pixels = calloc(size * size, channels);
  if (picture && [data length] >= (NSUInteger)(rowBytes * h)) {
    for (int y = 0; y < h; y++) {
      for (int i = 0; i < rowBytes; i++) {
        pixels[y * size * channels + i] = picture[y * rowBytes + i];
      }
    }
  }
  GLenum format = channels == 4 ? GL_RGBA : GL_RGB;
  GLuint texture;
  glGenTextures(1, &texture);
  glBindTexture(GL_TEXTURE_2D, texture);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glTexImage2D(GL_TEXTURE_2D, 0, format, size, size, 0, format,
               GL_UNSIGNED_BYTE, pixels);
  free(pixels);
  [pool drain];
  return texture;
}

// Draws the part of a texture from (u0, v0) to (u, v) into a rectangle.
static void drawTexture(GLuint texture, CGFloat x, CGFloat y, CGFloat w,
                        CGFloat h, GLfloat u0, GLfloat v0, GLfloat u,
                        GLfloat v) {
  GLfloat texCoords[8] = {u0, v0, u, v0, u, v, u0, v};
  setColor(1, 1, 1, 1);
  glEnable(GL_TEXTURE_2D);
  glBindTexture(GL_TEXTURE_2D, texture);
  glEnableClientState(GL_TEXTURE_COORD_ARRAY);
  glTexCoordPointer(2, GL_FLOAT, 0, texCoords);
  fillRect(x, y, w, h);
  glDisableClientState(GL_TEXTURE_COORD_ARRAY);
  glDisable(GL_TEXTURE_2D);
}

// Draws one cell of a sprite sheet, cells 4 to a row in a texture textureSize
// pixels square, at 2 pixels a point, with the point (cellX, cellY) in the
// cell at (x, y).
static void drawSprite(GLuint texture, int textureSize, int cellWidth,
                       int cellHeight, int frame, int cellX, int cellY,
                       CGFloat x, CGFloat y) {
  GLfloat u0 = (GLfloat)((frame & 3) * cellWidth) / textureSize;
  GLfloat v0 = (GLfloat)((frame >> 2) * cellHeight) / textureSize;
  drawTexture(texture, x - cellX * 0.5f, y - cellY * 0.5f, cellWidth * 0.5f,
              cellHeight * 0.5f, u0, v0,
              u0 + (GLfloat)cellWidth / textureSize,
              v0 + (GLfloat)cellHeight / textureSize);
}

// A baseball, with its red seams turned by spin radians.
static void drawBaseball(CGFloat x, CGFloat y, CGFloat r, CGFloat spin) {
  setColor(0.55f, 0.55f, 0.5f, 1); // Outline.
  fillCircle(x, y, r + 0.6f);
  setColor(0.86f, 0.85f, 0.8f, 1);
  fillCircle(x, y, r);
  setColor(1, 1, 1, 1); // Highlight.
  fillCircle(x - r * 0.2f, y - r * 0.2f, r * 0.72f);
  if (r < 3) {
    return; // Too small for seams.
  }

  // Each seam is part of a circle just outside the ball, on either side,
  // so the two curve toward each other. Stitches cross them.
  CGFloat c = cosf(spin), s = sinf(spin);
  CGFloat thickness = r * 0.14f < 0.8f ? 0.8f : r * 0.14f;
  setColor(0.85f, 0.1f, 0.1f, 1);
  for (int side = -1; side <= 1; side += 2) {
    CGFloat lastX = 0, lastY = 0;
    for (int i = 0; i <= 6; i++) {
      CGFloat a = (i / 6.0f - 0.5f) * 1.7f;
      CGFloat ax = side * (1.35f * r - 0.95f * r * cosf(a));
      CGFloat ay = 0.95f * r * sinf(a);
      CGFloat px = x + ax * c - ay * s, py = y + ax * s + ay * c;
      if (i > 0) {
        drawLine(lastX, lastY, px, py, thickness);
      }
      if (r >= 5 && i > 0 && i < 6) {
        // Across the seam, toward and away from its circle's center.
        CGFloat nx = -side * cosf(a) * r * 0.22f, ny = sinf(a) * r * 0.22f;
        CGFloat tx = nx * c - ny * s, ty = nx * s + ny * c;
        drawLine(px - tx, py - ty, px + tx, py + ty, thickness * 0.8f);
      }
      lastX = px;
      lastY = py;
    }
  }
}

@implementation BaseballView

+ (Class)layerClass {
  return [CAEAGLLayer class];
}

- (instancetype)initWithFrame:(CGRect)rect {
  if ((self = [super initWithFrame:rect])) {
    width = [self bounds].size.width;
    height = [self bounds].size.height;
    for (int i = 0; i <= CIRCLE_SEGMENTS; i++) {
      float angle = 6.2831853f * i / CIRCLE_SEGMENTS;
      circleCos[i] = cosf(angle);
      circleSin[i] = sinf(angle);
    }

    [(CALayer *)[self layer] setOpaque:YES];
    context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES1];
    [EAGLContext setCurrentContext:context];
    glGenFramebuffersOES(1, &framebuffer);
    glGenRenderbuffersOES(1, &renderbuffer);
    glBindFramebufferOES(GL_FRAMEBUFFER_OES, framebuffer);
    glBindRenderbufferOES(GL_RENDERBUFFER_OES, renderbuffer);
    [context renderbufferStorage:GL_RENDERBUFFER_OES fromDrawable:[self layer]];
    glFramebufferRenderbufferOES(GL_FRAMEBUFFER_OES, GL_COLOR_ATTACHMENT0_OES,
                                 GL_RENDERBUFFER_OES, renderbuffer);
    glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES,
                                    GL_RENDERBUFFER_WIDTH_OES, &pixelWidth);
    glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES,
                                    GL_RENDERBUFFER_HEIGHT_OES, &pixelHeight);

    fieldTexture = loadTexture("field", "rgb", FIELD_WIDTH, FIELD_HEIGHT, 3,
                               FIELD_TEXTURE_SIZE);
    logoTexture = loadTexture("logo", "rgba", LOGO_WIDTH, LOGO_HEIGHT, 4,
                              LOGO_TEXTURE_SIZE);
    pitcherTexture = loadTexture("pitcher", "rgba", PITCHER_WIDTH,
                                 PITCHER_HEIGHT, 4, PITCHER_WIDTH);
    batterTexture = loadTexture("batter", "rgba", BATTER_WIDTH, BATTER_HEIGHT,
                                4, BATTER_WIDTH);
    pitchTicks = 72; // Until the first pitch, for drawing the zone.
    bestHomeRuns = (int)loadInteger(BEST_KEY);
    gamesPlayed = (int)loadInteger(GAMES_PLAYED_KEY);
    bestStreak = (int)loadInteger(BEST_STREAK_KEY);
    perfectGames = (int)loadInteger(PERFECT_GAMES_KEY);
    SoundSetEnabled(!loadInteger(SOUND_OFF_KEY));
    state = StateTitle;
  }
  return self;
}

- (void)dealloc {
  [context release];
  [super dealloc];
}

// Where things are on the field.

- (CGFloat)pictureX:(CGFloat)x {
  return x / PICTURE_WIDTH * width;
}

- (CGFloat)pictureY:(CGFloat)y {
  return y / PICTURE_HEIGHT * height;
}

// The middle of home plate and the mound.
- (CGFloat)centerX {
  return [self pictureX:512];
}

// Where the batter stands, in the batter's box left of home plate: the
// outside of his front foot, just inside the inside line of the box, clear
// of the plate and the umpire, and far enough back in the box that the bat
// head meets the ball over the plate.
- (CGPoint)batterFeet {
  CGPoint feet;
  feet.x = [self pictureX:410];
  feet.y = [self pictureY:1350];
  return feet;
}

// Where the ball is as it crosses home plate, knee high to the batter.
- (CGFloat)hitY {
  return [self pictureY:1120];
}

// Where a pitch that isn't hit is gone, behind the umpire's head.
- (CGFloat)catchY {
  return [self pictureY:1261];
}

- (CGFloat)moundY {
  return [self pictureY:733]; // The rubber.
}

// Where the ball leaves the pitcher's hand, as in the picture of the
// release.
- (CGPoint)pitcherRelease {
  CGPoint hand;
  hand.x = [self centerX] - 3.6f;
  hand.y = [self moundY] - 47.9f;
  return hand;
}

// Which picture of the pitcher to show: standing, then lifting the leg and
// raising the arm at the end of the windup, the release as the ball is
// pitched, and the follow through.
- (int)pitcherFrame {
  if (state == StateWindup) {
    if (stateTicks > WINDUP_ARM_TICKS) {
      return 0;
    }
    return 1 + (int)((1 - (CGFloat)stateTicks / WINDUP_ARM_TICKS) * 2.99f);
  }
  if (state == StatePitch) {
    CGFloat ticks = ballProgress * pitchTicks; // Since the release.
    return ticks < 4 ? 4 : ticks < 10 ? 5 : 6;
  }
  return state == StateResult ? 6 : 0;
}

// Which picture of the batter to show: the stance, then lifting the front
// foot as the pitcher does and striding as the ball comes, and the swing.
- (int)batterFrame {
  if (swung) {
    int frame = 3 + (swingTicks >> 1); // 2 ticks a picture.
    return frame < 6 ? frame : 6;
  }
  if (state == StateWindup) {
    return stateTicks > WINDUP_ARM_TICKS ? 0 : 1;
  }
  return state == StatePitch ? 2 : 0;
}

// How far the ball has come from the pitcher's hand toward home plate, as
// seen on the screen: 0 in the hand and 1 at the plate. It speeds up as it
// comes closer. Progress is how far it has really come, likewise from 0 to 1.
// How far away the ball is, compared to when it crosses the plate.
- (CGFloat)depthAt:(CGFloat)progress {
  return PITCH_DEPTH + (1 - PITCH_DEPTH) * progress;
}

- (CGFloat)towardPlateAt:(CGFloat)progress {
  CGFloat depth = [self depthAt:progress];
  return (1 / depth - 1 / PITCH_DEPTH) / (1 - 1 / PITCH_DEPTH);
}

- (CGFloat)ballYAt:(CGFloat)progress {
  CGFloat releaseY = [self pitcherRelease].y;
  return releaseY + ([self hitY] - releaseY) * [self towardPlateAt:progress];
}

- (void)placeBall {
  CGPoint release = [self pitcherRelease];
  CGFloat toward = [self towardPlateAt:ballProgress];
  ballX = release.x + ([self centerX] - release.x) * toward;
  ballY = release.y + ([self hitY] - release.y) * toward;
  ballRadius = BALL_RADIUS / [self depthAt:ballProgress];
}

// The game.

- (void)startGame {
  swings = 0;
  homeRuns = 0;
  streak = 0;
  longestStreak = 0;
  saveInteger(GAMES_PLAYED_KEY, ++gamesPlayed);
  [self startWindup];
}

- (void)endGame {
  state = StateGameOver;
  celebrationTicks = 0;
  for (int i = 0; i < MAX_SPARKS; i++) {
    sparks[i].active = NO;
  }
  newBest = homeRuns > bestHomeRuns;
  newBestStreak = longestStreak > bestStreak;
  perfectGame = homeRuns == SWINGS_PER_GAME;
  if (perfectGame) {
    saveInteger(PERFECT_GAMES_KEY, ++perfectGames);
  }
  if (newBest || newBestStreak || perfectGame) {
    SoundPlay(SoundCheer);
  }
  if (newBest) {
    bestHomeRuns = homeRuns;
    saveInteger(BEST_KEY, bestHomeRuns);
  }
  if (newBestStreak) {
    bestStreak = longestStreak;
    saveInteger(BEST_STREAK_KEY, bestStreak);
  }
}

- (void)startWindup {
  state = StateWindup;
  stateTicks = 45 + (int)(nextRandom() & 63);
  swung = NO;
  swingTicks = 0;
  ballVisible = NO;
  inField = NO;
}

- (void)startPitch {
  state = StatePitch;
  ballVisible = YES;
  pitchTicks = 54 + 36 * randomUnit(); // To reach the plate.
  ballProgress = 0;
  [self placeBall];
  SoundPlay(SoundPitch);
}

- (void)showResult:(const char *)text
            detail:(const char *)detail
             ticks:(int)ticks {
  resultText = text;
  detailText = detail;
  state = StateResult;
  stateTicks = ticks;
}

- (void)swing {
  swung = YES;
  swingTicks = 0;
  SoundPlay(SoundSwing);
  CGFloat offset = (ballProgress - 1) * pitchTicks; // Negative is early.
  CGFloat distance = absf(offset);
  if (distance > ZONE) {
    return; // A miss. The ball carries on past the plate.
  }

  BOOL early = offset < 0;
  int chance;
  const char *detail;
  if (distance <= PERFECT) {
    chance = 100;
    detail = "PERFECT!";
  } else if (distance <= SLIGHT) {
    chance = 50;
    detail = early ? "SLIGHTLY EARLY" : "SLIGHTLY LATE";
  } else {
    chance = 10;
    detail = early ? "EARLY" : "LATE";
  }

  swings++;
  if ((int)(nextRandom() % 100) < chance) {
    homeRuns++;
    if (++streak > longestStreak) {
      longestStreak = streak;
    }
    if (streak == 2) {
      appendText(streakText, 0, "BACK TO BACK!");
    } else {
      appendText(streakText, appendNumber(streakText, 0, streak), " IN A ROW!");
    }
    resultIsHomeRun = YES;
    // How far it goes, in feet: the better the timing, the further.
    int shortest = chance == 100 ? 400 : chance == 50 ? 375 : 340;
    int longest = chance == 100 ? 450 : chance == 50 ? 405 : 375;
    // Without %, which armv6 has no instruction for.
    hitDistance =
        shortest + (int)(randomUnit() * (longest - shortest + 0.99f));
    appendText(distanceText, appendNumber(distanceText, 0, hitDistance),
               " FT");
    [self startHomeRunFlight];
    [self showResult:"HOME RUN!" detail:detail ticks:flightTicks + 50];
    SoundPlay(SoundPop);
    SoundPlay(SoundCheer);
  } else {
    // Half the time the ball lands on the outfield grass. Otherwise early
    // swings pull it away to the left, late ones to the right.
    resultIsHomeRun = NO;
    streak = 0;
    inField = nextRandom() & 1;
    if (inField) {
      [self startGrassFlight];
    } else {
      ballDX = early ? -7 : 7;
      ballDY = -3;
      ballShrink = 0.985f;
    }
    [self showResult:"MISS" detail:detail ticks:90];
    SoundPlay(SoundCrack);
  }
}

// A home run lands in the stands, further back the further it's hit, and
// anywhere from left field to right. It flies higher and longer too.
- (void)startHomeRunFlight {
  CGFloat far = (hitDistance - 340) / 110.0f; // 0 to 1.
  CGFloat frontRow = [self pictureY:330], backRow = [self pictureY:185];
  flightStartX = ballX;
  flightStartY = ballY;
  landX = [self centerX] + (randomUnit() * 2 - 1) * width * 0.38f;
  landY = frontRow + (backRow - frontRow) * far;
  arcHeight = 18 + 14 * far;
  flightTicks = 60 + (int)(25 * far);
  flightTick = 0;
}

// A ball hit into the field lands on the outfield grass, short of the wall,
// anywhere from left field to right.
- (void)startGrassFlight {
  CGFloat far = randomUnit(); // 0 to 1.
  CGFloat shallow = [self pictureY:560], deep = [self pictureY:430];
  flightStartX = ballX;
  flightStartY = ballY;
  landX = [self centerX] + (randomUnit() * 2 - 1) * width * 0.38f;
  landY = shallow + (deep - shallow) * far;
  arcHeight = 10 + 10 * far;
  flightTicks = 40 + (int)(20 * far);
  flightTick = 0;
}

// A ring of sparks from a random point, in a random color.
- (void)burst {
  CGFloat x = width * (0.15f + 0.7f * randomUnit());
  CGFloat y = height * (0.15f + 0.5f * randomUnit());
  int color = (int)(((nextRandom() & 1023) * FIREWORK_COLORS) >> 10);
  CGFloat directionX = 1, directionY = 0;
  int slot = 0;
  for (int i = 0; i < BURST_SPARKS; i++) {
    while (slot < MAX_SPARKS && sparks[slot].active) {
      slot++;
    }
    if (slot == MAX_SPARKS) {
      return;
    }
    Spark *spark = &sparks[slot];
    CGFloat speed = 2.5f + 2 * randomUnit();
    spark->active = YES;
    spark->x = x;
    spark->y = y;
    spark->dx = directionX * speed;
    spark->dy = directionY * speed;
    spark->ticksLeft = BURST_TICKS;
    spark->color = color;
    CGFloat nextX = directionX * BURST_COS - directionY * BURST_SIN;
    directionY = directionX * BURST_SIN + directionY * BURST_COS;
    directionX = nextX;
  }
}

- (void)celebrate {
  celebrationTicks++;
  // (% by a constant is fine: the compiler turns it into a multiply.)
  // A perfect game gets twice as many, and they keep going.
  if (perfectGame ? celebrationTicks % (BURST_INTERVAL / 2) == 1
                  : celebrationTicks % BURST_INTERVAL == 1 &&
                        (celebrationTicks < BURST_INTERVAL * BURST_COUNT ||
                         newBest)) {
    [self burst];
  }
  for (int i = 0; i < MAX_SPARKS; i++) {
    Spark *spark = &sparks[i];
    if (spark->active) {
      spark->x += spark->dx;
      spark->y += spark->dy;
      spark->dy += BURST_GRAVITY;
      spark->active = --spark->ticksLeft > 0;
    }
  }
}

- (void)update {
  if (swung) {
    swingTicks++;
  }
  if (state == StateGameOver && homeRuns > 0) {
    [self celebrate];
  }

  if (state == StateWindup) {
    if (--stateTicks <= 0) {
      [self startPitch];
    }
  } else if (state == StatePitch) {
    ballProgress += 1 / pitchTicks;
    [self placeBall];
    if (ballY + ballRadius >= [self catchY]) {
      ballVisible = NO;
      swings++;
      SoundPlay(SoundMitt);
      resultIsHomeRun = NO;
      streak = 0;
      [self showResult:"MISS"
                detail:swung ? "SWING AND MISS" : "NO SWING"
                 ticks:90];
    }
  } else if (state == StateResult) {
    if (ballVisible && (resultIsHomeRun || inField)) {
      CGFloat t = (CGFloat)++flightTick / flightTicks;
      if (t > 1) {
        t = 1; // On the grass, where it stays.
      }
      // Along the ground it slows as it goes, being further away.
      CGFloat along = 1 - (1 - t) * (1 - t);
      shadowX = flightStartX + (landX - flightStartX) * along;
      shadowY = flightStartY + (landY - flightStartY) * along;
      ballX = shadowX;
      ballY = shadowY - arcHeight * 4 * t * (1 - t);
      // Smaller as it goes away, less so on the grass, nearer than the stands.
      ballRadius = BALL_RADIUS * (1 - (inField ? 0.5f : 0.65f) * along);
      if (t >= 1 && resultIsHomeRun) {
        ballVisible = NO; // Into the crowd.
      }
    } else if (ballVisible) {
      ballX += ballDX;
      ballY += ballDY;
      ballRadius *= ballShrink;
      // Gone over the wall, or out of sight.
      if (ballY < [self pictureY:125] || ballRadius < 1 || ballX < -10 ||
          ballX > width + 10) {
        ballVisible = NO;
      }
    }
    if (--stateTicks <= 0) {
      if (swings >= SWINGS_PER_GAME) {
        [self endGame];
      } else {
        [self startWindup];
      }
    }
  }
}

static BOOL pointInRect(CGPoint point, CGRect rect) {
  return point.x >= rect.origin.x &&
         point.x < rect.origin.x + rect.size.width &&
         point.y >= rect.origin.y && point.y < rect.origin.y + rect.size.height;
}

// A button: a dark box with a white border, and its label, if it has one, in
// the middle.
static void drawButton(CGRect frame, const char *label, CGFloat size) {
  CGFloat bx = frame.origin.x, by = frame.origin.y;
  CGFloat bw = frame.size.width, bh = frame.size.height;
  setColor(0, 0, 0, 0.45f);
  fillRect(bx, by, bw, bh);
  setColor(1, 1, 1, 0.9f);
  fillRect(bx, by, bw, 2);
  fillRect(bx, by + bh - 2, bw, 2);
  fillRect(bx, by, 2, bh);
  fillRect(bx + bw - 2, by, 2, bh);
  if (label) {
    drawText(label, bx + bw * 0.5f, by + (bh - size * 1.2f) * 0.5f, size, 1,
             1, 1);
  }
}

// A house, with a roof and a door, around (x, y).
static void drawHomeIcon(CGFloat x, CGFloat y) {
  setColor(1, 1, 1, 0.95f);
  fillQuad(x, y - 9, x + 10, y - 1, x - 10, y - 1, x, y - 9);
  fillRect(x - 6.5f, y - 1, 13, 9);
  setColor(0.15f, 0.15f, 0.15f, 1); // The door.
  fillRect(x - 2, y + 2.5f, 4, 5.5f);
}

// A circular arrow, going around clockwise, around (x, y).
static void drawRestartIcon(CGFloat x, CGFloat y) {
  const CGFloat r = 7.5f;
  setColor(1, 1, 1, 0.95f);
  // From a little below the right, around to the upper right.
  for (int i = 2; i < 21; i++) {
    drawLine(x + circleCos[i] * r, y + circleSin[i] * r,
             x + circleCos[i + 1] * r, y + circleSin[i + 1] * r, 2.5f);
  }
  // The arrowhead, pointing on around the circle.
  CGFloat ex = x + circleCos[21] * r, ey = y + circleSin[21] * r;
  CGFloat tx = -circleSin[21], ty = circleCos[21]; // Along the circle.
  CGFloat nx = circleCos[21], ny = circleSin[21];  // Out from the middle.
  fillQuad(ex + tx * 4.5f, ey + ty * 4.5f, ex + nx * 4.5f - tx * 1.5f,
           ey + ny * 4.5f - ty * 1.5f, ex - nx * 4.5f - tx * 1.5f,
           ey - ny * 4.5f - ty * 1.5f, ex + tx * 4.5f, ey + ty * 4.5f);
}

// The sound on/off button, on the title screen.
- (CGRect)soundButtonFrame {
  CGRect frame = {{[self centerX] - 80, 372}, {160, 34}};
  return frame;
}

// While playing, home, back to the title screen, on the left on the grass
// below the outfield wall, and restart, a new game, on the right.
- (BOOL)playing {
  return state != StateTitle && state != StateGameOver;
}

- (CGRect)homeButtonFrame {
  CGRect frame = {{6, 131}, {32, 28}};
  return frame;
}

- (CGRect)restartButtonFrame {
  CGRect frame = {{width - 38, 131}, {32, 28}};
  return frame;
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
  CGPoint point = [[touches anyObject] locationInView:self];
  if (state == StateTitle && pointInRect(point, [self soundButtonFrame])) {
    BOOL enabled = !SoundIsEnabled();
    SoundSetEnabled(enabled);
    saveInteger(SOUND_OFF_KEY, !enabled);
    SoundPlay(SoundCrack); // Only heard when turning sound on.
  } else if ([self playing] && pointInRect(point, [self homeButtonFrame])) {
    state = StateTitle;
    ballVisible = NO;
    swung = NO;
  } else if ([self playing] &&
             pointInRect(point, [self restartButtonFrame])) {
    [self startGame];
  } else if (state == StateTitle || state == StateGameOver) {
    [self startGame];
  } else if (state == StatePitch && !swung) {
    [self swing];
  }
}

// Drawing.

- (void)drawField {
  drawTexture(fieldTexture, 0, 0, width, height, 0, 0,
              (GLfloat)FIELD_WIDTH / FIELD_TEXTURE_SIZE,
              (GLfloat)FIELD_HEIGHT / FIELD_TEXTURE_SIZE);
}

// The corners of the part of the zone the ball is in between two points in
// its progress, in perspective: left and right at the far end, then right
// and left at the near end.
- (void)zoneFrom:(CGFloat)from to:(CGFloat)to corners:(CGFloat *)corners {
  CGFloat cx = [self centerX];
  CGFloat farHalf = ZONE_HALF_WIDTH / [self depthAt:from];
  CGFloat nearHalf = ZONE_HALF_WIDTH / [self depthAt:to];
  CGFloat farY = [self ballYAt:from], nearY = [self ballYAt:to];
  if (nearY > [self catchY]) {
    nearY = [self catchY]; // The ball is gone by then.
  }
  CGFloat points[8] = {
      cx - farHalf, farY, cx + farHalf, farY,
      cx + nearHalf, nearY, cx - nearHalf, nearY,
  };
  for (int i = 0; i < 8; i++) {
    corners[i] = points[i];
  }
}

// Where the ball can be hit, brighter where the timing is nearly perfect.
- (void)drawZone {
  CGFloat c[8];
  [self zoneFrom:1 - SLIGHT / pitchTicks to:1 + SLIGHT / pitchTicks corners:c];
  setColor(1, 0.9f, 0.2f, 0.18f);
  fillQuad(c[0], c[1], c[2], c[3], c[4], c[5], c[6], c[7]);
  [self zoneFrom:1 - ZONE / pitchTicks to:1 + ZONE / pitchTicks corners:c];
  setColor(1, 0.9f, 0.2f, 0.12f);
  fillQuad(c[0], c[1], c[2], c[3], c[4], c[5], c[6], c[7]);
}

// The pitcher, standing on the rubber, facing home plate: one of the
// pictures in the pitcher texture.
- (void)drawPitcher {
  CGFloat x = [self centerX];
  CGFloat y = [self moundY];
  setColor(0, 0, 0, 0.25f); // Shadow on the mound.
  fillEllipse(x, y, 16, 4);
  drawSprite(pitcherTexture, PITCHER_WIDTH, PITCHER_CELL_WIDTH,
             PITCHER_CELL_HEIGHT, [self pitcherFrame], PITCHER_RUBBER_X,
             PITCHER_RUBBER_Y, x, y);
}

// The batter, seen from behind: one of the pictures in the batter texture.
- (void)drawBatter {
  CGPoint feet = [self batterFeet];
  setColor(0, 0, 0, 0.25f); // Shadow in the batter's box.
  fillEllipse(feet.x - 40, feet.y - 4, 44, 9);
  drawSprite(batterTexture, BATTER_WIDTH, BATTER_CELL_WIDTH,
             BATTER_CELL_HEIGHT, [self batterFrame], BATTER_FEET_X,
             BATTER_FEET_Y, feet.x, feet.y);
}

// The scoreboard is in the field picture, with HR and /20 on it. This adds
// the number of home runs after HR, and the swings used before /20.
- (void)drawScoreboard {
  char text[16];
  appendNumber(text, 0, homeRuns);
  drawTextAnchored(text, [self pictureX:228], [self pictureY:9], 30, 0, 1,
                   0.8f, 0);
  appendNumber(text, 0, swings);
  drawTextAnchored(text, [self pictureX:826], [self pictureY:14], 26, 1, 1, 1,
                   1);
}

- (void)drawOverlay {
  CGFloat cx = [self centerX];
  setColor(0, 0, 0, 0.55f);
  fillRect(0, 0, width, height);
  // Fireworks, fading out and shrinking, behind the text.
  for (int i = 0; i < MAX_SPARKS; i++) {
    if (state == StateGameOver && sparks[i].active) {
      CGFloat life = (CGFloat)sparks[i].ticksLeft / BURST_TICKS;
      const GLfloat *color = fireworkColors[sparks[i].color];
      setColor(color[0], color[1], color[2], life);
      fillCircle(sparks[i].x, sparks[i].y, 1.5f + 2.5f * life);
      setColor(1, 1, 1, life * life); // A hot center, cooling first.
      fillCircle(sparks[i].x, sparks[i].y, 1 + life);
    }
  }
  if (state == StateTitle) {
    drawTexture(logoTexture, cx - LOGO_WIDTH * 0.5f, 80, LOGO_WIDTH,
                LOGO_HEIGHT, 0, 0, (GLfloat)LOGO_WIDTH / LOGO_TEXTURE_SIZE,
                (GLfloat)LOGO_HEIGHT / LOGO_TEXTURE_SIZE);
    drawText("TAP TO PLAY", cx, 204, 26, 1, 1, 1);
    char text[32];
    if (bestHomeRuns > 0) {
      int length = appendNumber(text, appendText(text, 0, "BEST "),
                                bestHomeRuns);
      if (bestStreak > 0) {
        length = appendText(text, length, "   BEST STREAK ");
        appendNumber(text, length, bestStreak);
      }
      drawText(text, cx, 234, 17, 1, 0.9f, 0.3f);
    }
    if (gamesPlayed > 0) {
      int length = appendNumber(text, appendText(text, 0, "GAMES PLAYED "),
                                gamesPlayed);
      if (perfectGames > 0) {
        length = appendText(text, length, "   PERFECT GAMES ");
        appendNumber(text, length, perfectGames);
      }
      drawText(text, cx, 255, 14, 0.8f, 0.8f, 0.8f);
    }
    drawText("TAP TO SWING", cx, 286, 17, 0.85f, 0.85f, 0.85f);
    drawText("YOU GET 20 SWINGS", cx, 308, 17, 0.85f, 0.85f, 0.85f);

    drawButton([self soundButtonFrame],
               SoundIsEnabled() ? "SOUND: ON" : "SOUND: OFF", 17);
  } else {
    char text[32];
    appendNumber(text, appendText(text, 0, "HOME RUNS "), homeRuns);
    if (perfectGame) {
      BOOL flash = (celebrationTicks & 8) != 0;
      drawText("PERFECT GAME!", cx, 128, 32, 1, flash ? 1 : 0.85f,
               flash ? 1 : 0.2f);
    } else {
      drawText("GAME OVER", cx, 124, 38, 1, 0.3f, 0.25f);
    }
    drawText(text, cx, 190, 26, 1, 0.9f, 0.3f);
    if (homeRuns == 0) {
      // No best or streaks for a game without a single home run.
      drawText("Are you awake?", cx, 234, 20, 1, 1, 1);
      drawText("TAP TO PLAY AGAIN", cx, 290, 17, 1, 1, 1);
      return;
    }
    if (newBest) {
      drawText("NEW BEST!", cx, 226, 20, 1, 1, 1);
    } else {
      appendNumber(text, appendText(text, 0, "BEST "), bestHomeRuns);
      drawText(text, cx, 228, 17, 0.85f, 0.85f, 0.85f);
    }
    if (newBestStreak) {
      int length = appendText(text, 0, "NEW BEST STREAK: ");
      appendText(text, appendNumber(text, length, bestStreak), "!");
      drawText(text, cx, 254, 17, 1, 0.55f, 0.15f);
    } else {
      int length = appendText(text, 0, "LONGEST STREAK ");
      length = appendText(text, appendNumber(text, length, longestStreak),
                          " (BEST ");
      appendText(text, appendNumber(text, length, bestStreak), ")");
      drawText(text, cx, 256, 15, 0.85f, 0.85f, 0.85f);
    }
    drawText("TAP TO PLAY AGAIN", cx, 290, 17, 1, 1, 1);
  }
}

- (void)render {
  [EAGLContext setCurrentContext:context];
  glBindFramebufferOES(GL_FRAMEBUFFER_OES, framebuffer);
  glViewport(0, 0, pixelWidth, pixelHeight);
  glMatrixMode(GL_PROJECTION);
  glLoadIdentity();
  // Points, with y going down, like UIKit.
  glOrthof(0, width, height, 0, -1, 1);
  glMatrixMode(GL_MODELVIEW);
  glLoadIdentity();
  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glEnableClientState(GL_VERTEX_ARRAY);

  glClearColor(0.18f, 0.5f, 0.2f, 1);
  glClear(GL_COLOR_BUFFER_BIT);

  [self drawField];
  [self drawZone];
  [self drawPitcher];
  [self drawBatter];
  if (ballVisible) {
    BOOL flying = state == StateResult && (resultIsHomeRun || inField);
    setColor(0, 0, 0, 0.25f); // Shadow.
    fillEllipse(flying ? shadowX : ballX + 2, flying ? shadowY : ballY + 3,
                ballRadius, ballRadius * 0.6f);
    drawBaseball(ballX, ballY, ballRadius, ballY * 0.06f);
  }

  if (state == StateResult) {
    CGFloat cx = [self centerX];
    if (resultIsHomeRun) {
      BOOL flash = (stateTicks & 8) != 0;
      if (streak >= 2) {
        drawText(streakText, cx, 40, 20, 1, 0.55f, 0.15f);
      }
      drawText(resultText, cx, 63, 36, 1, flash ? 1 : 0.85f, flash ? 1 : 0.2f);
      drawText(distanceText, cx, 101, 24, 1, 0.85f, 0.2f);
      drawText(detailText, cx, 129, 15, 0.9f, 0.9f, 0.9f);
    } else {
      drawText(resultText, cx, 90, 28, 1, 1, 1);
      drawText(detailText, cx, 126, 17, 0.9f, 0.9f, 0.9f);
    }
  }
  [self drawScoreboard];
  if ([self playing]) {
    CGRect home = [self homeButtonFrame];
    CGRect restart = [self restartButtonFrame];
    drawButton(home, 0, 0);
    drawHomeIcon(home.origin.x + 16, home.origin.y + 14);
    drawButton(restart, 0, 0);
    drawRestartIcon(restart.origin.x + 16, restart.origin.y + 14);
  }
  if (state == StateTitle || state == StateGameOver) {
    [self drawOverlay];
  }

  glBindRenderbufferOES(GL_RENDERBUFFER_OES, renderbuffer);
  [context presentRenderbuffer:GL_RENDERBUFFER_OES];
}

- (void)tick {
  [self update];
  [self render];
}

@end
