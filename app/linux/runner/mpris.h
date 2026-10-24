#ifndef RUNNER_MPRIS_H_
#define RUNNER_MPRIS_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// Puts Tunes on the session bus as an MPRIS media player
// (org.mpris.MediaPlayer2.tunes), so the desktop's media keys, bar widgets,
// headphone buttons and playerctl see and drive it. The app reports what is
// playing over the "tunes/mpris" channel; commands go back the same way.
void mpris_start(FlView* view, GtkWindow* window);

#endif  // RUNNER_MPRIS_H_
