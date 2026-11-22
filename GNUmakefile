# Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause
#
# Update.app: keeps NextBSD up to date (nextbsd/nextbsd#661). The work is
# done by the settings apps' privileged helper, SettingsHelper
# (nextbsd-userland src/SettingsHelper, sh_update.c), whose client is
# apps-settings' Frameworks/NBSettings. It's compiled in from a checkout
# of apps-settings beside this one, as nextbsd-gnustep-apps clones them
# (NBSETTINGS= to use another), until NBSettings becomes a framework
# (nextbsd/nextbsd#627). Installed like the other desktop apps, in the
# USER domain (~/Applications) for now.

ifeq ($(GNUSTEP_MAKEFILES),)
 GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES)
endif
include $(GNUSTEP_MAKEFILES)/common.make

NBSETTINGS ?= ../apps-settings/Frameworks/NBSettings

APP_NAME = Update
Update_OBJC_FILES = main.m UPController.m UPViews.m
Update_HEADER_FILES = UPController.h UPViews.h
Update_RESOURCE_FILES = Resources/Update.png
Update_APPLICATION_ICON = Update.png
Update_OBJCFLAGS = -Wall -Wextra -Wno-unused-parameter
Update_SUBPROJECTS = $(NBSETTINGS)
Update_INCLUDE_DIRS = -I$(NBSETTINGS)

# NextBSD's system libraries live in /usr/lib/system: liblaunch and the
# Mach calls for the helper's client.
SYSTEM_LIBDIR = /usr/lib/system
ADDITIONAL_LDFLAGS += -L$(SYSTEM_LIBDIR) -Wl,-rpath,$(SYSTEM_LIBDIR)
Update_GUI_LIBS += -llaunch -lsystem_kernel

include $(GNUSTEP_MAKEFILES)/application.make
