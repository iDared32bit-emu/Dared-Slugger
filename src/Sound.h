/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

// Sound effects, played through OpenAL.

#include "System.h"

typedef enum {
  SoundPitch, // The ball leaving the pitcher's hand.
  SoundSwing, // The bat swishing through.
  SoundCrack, // The bat hitting the ball, not well enough for a home run.
  SoundPop,   // The bat hitting the ball for a home run.
  SoundMitt,  // A pitch not hit, into the catcher's mitt.
  SoundCheer, // The crowd, for a home run or a new best.
  SoundCount,
} Sound;

// Loads the sounds. If anything fails, the game simply stays silent.
void SoundInit(void);
void SoundPlay(Sound sound);

// Sound is on unless turned off; SoundPlay does nothing while it's off.
void SoundSetEnabled(BOOL enabled);
BOOL SoundIsEnabled(void);
