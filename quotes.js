export const FISHING_QUOTES = [
  "You should've seen the one that got away!",
  'A bad day fishing beats a good day at work.',
  "It's called fishing, not catching!",
  'Just one more cast...',
  'The fish are biting. Just not my hook.',
  'The one that got away grows an inch every time you tell the story.',
  'Fish tremble at the mention of my name.',
  'Oh my cod!',
  'Holy mackerel!',
  'Carpe diem. Carp tomorrow.',
  'For the halibut!',
  'What a load of carp!',
  'The fishing was good. It was the catching that was bad.',
  "Fish don't care how expensive your rod is.",
  "The two best times to fish are when it's raining and when it isn't.",
  'They were biting yesterday.',
  'Should\'ve been here last week.',
  "I'm not catching fish. I'm collecting data.",
  'The fish clearly haven\'t read the forecast.',
  'Somewhere, a fish is telling a story about you.',
  'Every fish has a tale.',
  'Small fish. Big personality.',
  'A reel achievement!',
];

/**
 * Choose the next quote, starting with the first for a new installation.
 */
export function nextQuoteIndex(previous, count = FISHING_QUOTES.length) {
  if (!Number.isInteger(count) || count < 1) return 0;
  if (!Number.isInteger(previous) || previous < 0 || previous >= count) return 0;
  return (previous + 1) % count;
}
