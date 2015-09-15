import Base: now

Base.convert(::Type{DateTime}, dt::ZonedDateTime) = localtime(dt)
@vectorize_1arg ZonedDateTime DateTime

now(tz::TimeZone) = ZonedDateTime(Dates.unix2datetime(time()), tz, from_utc=true)
