@echo off
echo (iniciando servidor)
if "%1"=="dev" ( echo modo (dev) )
set HOME_DIR=$HOME
if [ -f .env ] && docker compose up
