DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

int epochDay(DateTime d) =>
    (dateOnly(d).millisecondsSinceEpoch / Duration.millisecondsPerDay).round();

DateTime fromEpochDay(int day) =>
    DateTime.fromMillisecondsSinceEpoch(day * Duration.millisecondsPerDay);

bool isSameDay(DateTime a, DateTime b) => epochDay(a) == epochDay(b);
