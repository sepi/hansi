// SPDX-License-Identifier: AGPL-3.0-or-later

/// Debounce delay applied after each keystroke before firing a search.
const kDebounceDelay = Duration(milliseconds: 300);

/// Delay after search results arrive before the query is added to history.
const kHistoryAddDelay = Duration(milliseconds: 1500);

/// Maximum number of entries kept in the recent-searches history.
const kMaxHistory = 100;

/// Pixels before the list bottom that triggers loading the next page of results.
const kScrollLoadThreshold = 200.0;
