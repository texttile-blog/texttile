/* When a comment arrived, in the reader's own zone: "29. Oktober um
   14:05", with the year once it is another one. The server knows no
   zone, so it writes the day alone and this adds the hour.

   English asks for the British shape, day before month, because that
   is how the reader pages write every other date. Without a zone the
   browser's own is used; an imported comment passes "UTC". */

export function commentMoment(at, lang, now = new Date(), timeZone) {
  const locale = lang === "en" ? "en-GB" : lang
  const year = (d) => new Intl.DateTimeFormat("en", {year: "numeric", timeZone}).format(d)

  return at.toLocaleString(locale, {
    day: "numeric",
    month: "long",
    year: year(at) === year(now) ? undefined : "numeric",
    hour: "2-digit",
    minute: "2-digit",
    timeZone,
  })
}
