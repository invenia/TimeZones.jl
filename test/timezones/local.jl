using Fixtures

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
        mock_readall = mock(return_value="Time Zone:  $testname\n")
        patchers = [
            Patcher(Base, :readall, mock_readall)
        ]
        patch(patchers) do
            @test TimeZones._get_localzone_mac() == testname
        end

        # Determine timezone from /etc/localtime (Mac).
        mock_readall = mock(return_value="")
        mock_readlink = mock(return_value="/usr/share/zoneinfo/$testname")
        patchers = [
            Patcher(Base, :readall, mock_readall)
            Patcher(Base, :readlink, mock_readlink)
        ]
        patch(patchers) do
            @test TimeZones._get_localzone_mac() == testname
        end

        # Determine timezone from /etc/timezone
        mock_isfile(filename) = filename == "/etc/timezone"
        fake_open(filename) = IOBuffer("$testname #Works with comments\n")
        # mock_open = mock(return_value=IOBuffer("$testname #Works with comments\n"))
        patchers = [
            Patcher(Base, :isfile, mock_isfile)
            Patcher(Base, :open, fake_open)
        ]
        patch(patchers) do
            @test TimeZones._get_localzone_unix() == testname
        end

        # Determine timezone from /etc/conf.d/clock
        mock_isfile2(filename) = filename == "/etc/conf.d/clock"
        mock_open2 = mock(return_value=IOBuffer("\n\nTIMEZONE=\"$testname\""))
        patchers = [
            Patcher(Base, :isfile, mock_isfile2)
            Patcher(Base, :open, mock_open2)
        ]
        patch(patchers) do
            @test TimeZones._get_localzone_unix() == testname
        end

        # Determine timezone from /etc/localtime (Unix).
        mock_isfile(filename) = filename == false
        mock_islink = mock(return_value=true)
        mock_readlink = mock(return_value="/usr/share/zoneinfo/$testname")
        patchers = [
            Patcher(Base, :isfile, mock_isfile)
            Patcher(Base, :islink, mock_islink)
            Patcher(Base, :readlink, mock_readlink)
        ]
        patch(patchers) do
            @test TimeZones._get_localzone_unix() == testname
        end

        # Unable to determine timezone (Unix).
        mock_isfile(filename) = filename == false
        mock_islink = mock(return_value=false)
        patchers = [
            Patcher(Base, :isfile, mock_isfile)
            Patcher(Base, :islink, mock_islink)
        ]
        patch(patchers) do
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
