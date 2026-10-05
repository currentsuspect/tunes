import 'dart:math';

/// The rules for what plays next when shuffle is turned on or off.
///
/// Pure, so they can be tested without a decoder. The player keeps two orders:
/// the one it was given (what "in order" means) and the one it is playing. A
/// toggle only ever changes what is still to come: the song on and everything
/// already played stay exactly where they are.

/// The queue with everything after [index] put in a random order.
///
/// What was played, and what is playing, stays in place, so the queue still
/// reads as a history followed by a future. Returns a new list.
List<T> shuffleAfter<T>(List<T> queue, int index, Random random) {
  if (queue.length < 3 || index < 0 || index >= queue.length - 1) {
    return List<T>.of(queue);
  }
  final head = queue.sublist(0, index + 1);
  final tail = queue.sublist(index + 1)..shuffle(random);
  return [...head, ...tail];
}

/// The queue with everything after [index] back in the order it was given.
///
/// "Next" becomes the next song after the current one in the original list,
/// the way a list reads, and it runs on to the end of that list. Songs before
/// the current one in the list that were never reached are left out rather than
/// dragged in behind it: turning shuffle off continues from here, it does not
/// restart. If the current song is not in [canonical] (a pick the radio added),
/// nothing follows it from the list.
List<T> inOrderAfter<T>(List<T> queue, List<T> canonical, int index) {
  if (index < 0 || index >= queue.length) return List<T>.of(queue);
  final current = queue[index];
  final head = queue.sublist(0, index + 1);
  final at = canonical.indexOf(current);
  final tail = at < 0 ? const [] : canonical.sublist(at + 1);
  return [...head, ...tail];
}

/// Whether two queues differ after [index]: nothing to tell the decoder when
/// a toggle left the future as it was.
bool sameFuture<T>(List<T> a, List<T> b, int index) {
  if (a.length != b.length) return false;
  for (var i = index + 1; i < a.length; i++) {
    if (!identical(a[i], b[i]) && a[i] != b[i]) return false;
  }
  return true;
}
