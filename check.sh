#!/bin/sh
luacheck . --globals import VERSION preQuit onAnyEvent init --ignore 212 542 611 612 613 614
