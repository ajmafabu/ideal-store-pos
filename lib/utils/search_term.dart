/// Text typed into a search box, made safe for a PostgREST or() filter.
/// Commas, brackets, quotes, `*`, `%` and backslashes have a meaning there,
/// so "Kumar, R" or "(Shop)" used to make the search fail.
String searchTerm(String query) => query.replaceAll(RegExp(r'[,()*%\\"]'), ' ').trim();
