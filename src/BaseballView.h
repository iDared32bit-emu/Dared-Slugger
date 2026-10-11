/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#include "System.h"

typedef enum {
  StateTitle,    // Tap to play.
  StateWindup,   // The pitcher gets ready.
  StatePitch,    // The ball is on its way. Tap to swing.
  StateResult,   // Showing what happened to the pitch.
  StateGameOver, // Out of swings. Tap to play again.
} GameState;

@interface BaseballView : UIView {
  EAGLContext *context;
  GLuint framebuffer, renderbuffer;
  GLuint fieldTexture, logoTexture, pitcherTexture, batterTexture;
  GLint pixelWidth, pixelHeight;
  CGFloat width, height; // In points, what everything is drawn in.

  GameState state;
  int stateTicks; // Ticks left in the windup or result.
  int swings; // Pitches used up this game, swung at or not.
  int homeRuns;
  int streak; // Home runs in a row, up to the last pitch.
  char streakText[24];
  int longestStreak; // This game.
  int bestStreak;    // The longest in any game, saved between launches.
  BOOL newBestStreak; // The game just over set it.
  int bestHomeRuns; // The most in one game, saved between launches.
  BOOL newBest;     // The game just over set a new best.
  int gamesPlayed;  // Saved between launches.
  int perfectGames; // Games with every swing a home run, saved likewise.
  BOOL perfectGame; // The game just over was one.
  int celebrationTicks; // Ticks since the game over screen showed.

  BOOL ballVisible;
  CGFloat ballX, ballY, ballRadius;
  CGFloat ballDX, ballDY;
  CGFloat ballShrink; // Radius multiplier per tick, once the ball is hit.
  CGFloat ballProgress; // From the pitcher's hand (0) to the plate (1).
  CGFloat pitchTicks;   // How long this pitch takes to reach the plate.
  BOOL swung;         // The batter has swung at this pitch.
  int swingTicks;     // Ticks since the swing started.

  // A home run's flight, from where it was hit to where it lands in the
  // stands, in ticks.
  int hitDistance; // In feet.
  char distanceText[16];
  CGFloat flightStartX, flightStartY, landX, landY, arcHeight;
  CGFloat shadowX, shadowY; // Under the ball, on the ground.
  int flightTicks, flightTick;

  // What to show for the result of the pitch.
  const char *resultText;
  const char *detailText;
  BOOL resultIsHomeRun;
  BOOL inField; // A miss that was hit, landing on the outfield grass.
}
- (void)tick;
@end
