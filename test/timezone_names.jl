import TimeZones: TimeZone, timezone_names

names = timezone_names()

@test length(names) >= 429
@test isa(names, Array{AbstractString})
@test issorted(names)


# test TimeZones
@test string(TimeZone("UTC")) == "UTC"
@test_throws ErrorException TimeZone("Not a real time zone")
