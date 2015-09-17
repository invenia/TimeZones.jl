testnames = [
    "Africa/Abidjan",
    "America/Argentina/Buenos_Aires",
    "Africa/Dar_es_Salaam",
    "America/Port-au-Prince",
    "WET"
]

withenv("TZ" => nothing) do
    for testname in testnames

        # Determine timezone via systemsetup (Mac).
        mock_readall(cmd) = "Time Zone:  $testname\n"
        patches = [
            Patch(Base, :readall, mock_readall)
        ]
        patch(patches) do
            @test TimeZones._get_localzone_mac() == testname
        end

        # Determine timezone from /etc/localtime (Mac).
        mock_readall(cmd) = ""
        mock_readlink(filename) = "/usr/share/zoneinfo/$testname"
        patches = [
            Patch(Base, :readall, mock_readall)
            Patch(Base, :readlink, mock_readlink)
        ]
        patch(patches) do
            @test TimeZones._get_localzone_mac() == testname
        end

        # Determine timezone from /etc/timezone
        mock_isfile(filename) = filename == "/etc/timezone"
        mock_open(filename) = IOBuffer("$testname #Works with comments\n")
        patches = [
            Patch(Base, :isfile, mock_isfile)
            Patch(Base, :open, mock_open)
        ]
        patch(patches) do
            @test TimeZones._get_localzone_unix() == testname
        end

        # Determine timezone from /etc/conf.d/clock
        mock_isfile(filename) = filename == "/etc/conf.d/clock"
        mock_open(filename) = IOBuffer("\n\nTIMEZONE=\"$testname\"")
        patches = [
            Patch(Base, :isfile, mock_isfile)
            Patch(Base, :open, mock_open)
        ]
        patch(patches) do
            @test TimeZones._get_localzone_unix() == testname
        end

        # Determine timezone from /etc/localtime (Unix).
        mock_isfile(filename) = filename == "/etc/localtime"
        mock_islink(filename) = filename == "/etc/localtime"
        mock_readlink(filename) = "/usr/share/zoneinfo/$testname"
        patches = [
            Patch(Base, :isfile, mock_isfile)
            Patch(Base, :islink, mock_islink)
            Patch(Base, :readlink, mock_readlink)
        ]
        patch(patches) do
            @test TimeZones._get_localzone_unix() == testname
        end

        # Unable to determine timezone (Unix).
        mock_isfile(filename) = false
        mock_islink(filename) = false
        patches = [
            Patch(Base, :isfile, mock_isfile)
            Patch(Base, :islink, mock_islink)
        ]
        patch(patches) do
            @test_throws ErrorException TimeZones._get_localzone_unix()
        end

        # Test TZ environmental variable.
        withenv("TZ" => ":$testname") do
            @test TimeZones._get_localzone_unix() == testname
        end

        withenv("TZ" => ":bad") do
            @test_throws ErrorException TimeZones._get_localzone_unix()
        end

        withenv("TZ" => "") do
            @test_throws ErrorException TimeZones._get_localzone_unix()
        end
    end
end
