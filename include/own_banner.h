#pragma once

// Own fork: the banner "Міняємо екран, зачекайте…" after a short press of the button.
// It comes with a partial update in less than 1 second. The new screen from the server replaces it.
// Returns false if the panel cannot do a partial update now: then the function draws nothing.
bool display_show_change_banner(void);
