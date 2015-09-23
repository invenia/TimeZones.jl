Base.convert(::Type{DateTime}, dt::ZonedDateTime) = localtime(dt)
@vectorize_1arg ZonedDateTime DateTime
