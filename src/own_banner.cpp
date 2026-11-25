#include <display.h>
#include <display_internal.h>
#include <epd_driver.h>
#include <globals.h>
#include <own_banner.h>
#include <trmnl_log.h>

#include "displayed_image.h"
#include "own_banner_text.h"

#ifdef BB_EPAPER
// The banner: white text in a black box, in a white border. The border keeps it clear on a black screen.
#define OWN_BANNER_PAD_X  24 // from the box edge to the text
#define OWN_BANNER_PAD_Y  18
#define OWN_BANNER_BORDER 4

// Draws the banner into the frame buffer. inverse swaps black and white.
static void draw_banner(int x, int y, int w, int h, bool inverse) {
  const uint8_t light = inverse ? BBEP_BLACK : BBEP_WHITE; // the text and the border
  const uint8_t dark = inverse ? BBEP_WHITE : BBEP_BLACK; // the box
  const int b = OWN_BANNER_BORDER;
  bbep.fillRect(x, y, w, h, light);
  bbep.fillRect(x + b, y + b, w - 2 * b, h - 2 * b, dark);
  bbep.drawSprite(own_banner_text, OWN_BANNER_TEXT_W, OWN_BANNER_TEXT_H, OWN_BANNER_TEXT_PITCH,
                  x + (w - OWN_BANNER_TEXT_W) / 2, y + (h - OWN_BANNER_TEXT_H) / 2, light);
}
#endif // BB_EPAPER

// The partial update changes only the pixels where the old and the new data of the panel differ.
// Outside the banner both keep the current image, so it stays on the panel. In the banner region the
// old data gets the inverse of the banner: then each pixel of the banner changes.
bool display_show_change_banner(void) {
#ifdef BB_EPAPER
  if (!bCanDoPartial) {
    Log_info("Banner: the panel memory has no 1-bit image, no partial update");
    return false;
  }
  display_prepare_message(); // the 1-bit panel and a 1-bit frame buffer
  if (bbep.getBuffer() == nullptr) {
    Log_error("Banner: no memory for the frame buffer");
    return false;
  }
  const int w = (OWN_BANNER_TEXT_W + 2 * (OWN_BANNER_PAD_X + OWN_BANNER_BORDER) + 7) & ~7; // whole bytes
  const int h = OWN_BANNER_TEXT_H + 2 * (OWN_BANNER_PAD_Y + OWN_BANNER_BORDER);
  const int x = ((bbep.width() - w) / 2) & ~7;
  const int y = (bbep.height() - h) / 2;

  draw_banner(x, y, w, h, true);
  bbep.writeRegion(x, y, w, h, PLANE_1); // the old data
  draw_banner(x, y, w, h, false);
  bbep.writeRegion(x, y, w, h, PLANE_0); // the new data
  bbep.refresh(REFRESH_PARTIAL, true);
  bbep.writeCmd(UC8151_PTOU); // partial out: the next image uses the full panel
  bbep.freeBuffer();

  // Draw the server image after the banner, also when it did not change.
  DisplayedImage::cover();
  need_to_refresh_display = 1;
  Log_info("Banner: shown at %d,%d (%dx%d)", x, y, w, h);
  return true;
#else
  return false;
#endif // BB_EPAPER
}
