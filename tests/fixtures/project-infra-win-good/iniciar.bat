@echo off
echo iniciando servidor
set HOME_DIR=%USERPROFILE%
if exist .env docker compose up
