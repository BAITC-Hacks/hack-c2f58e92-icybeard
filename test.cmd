@echo off
rem All tests (.NET, Python, web) in Docker: for Windows, where make and protoc.exe do not run.
docker run --rm -v "%~dp0.":/src:ro mcr.microsoft.com/dotnet/sdk:10.0 bash -c "tr -d '\r' < /src/scripts/test-docker.sh > /tmp/t.sh && bash /tmp/t.sh"
