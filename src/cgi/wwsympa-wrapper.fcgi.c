/* $Id$
 
  Sympa - SYsteme de Multi-Postage Automatique

  Copyright (c) 1997-1999 Institut Pasteur & Christophe Wolfhugel
  Copyright (c) 1997-2011 Comite Reseau des Universites
  Copyright (c) 2011-2014 GIP RENATER
 
  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 2 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include <unistd.h>

int main(int argn, char **argv, char **envp) {
    setreuid(geteuid(),geteuid()); // Added to fix the segfault
    setregid(getegid(),getegid()); // Added to fix the segfault
    argv[0] = WWSYMPA;
    return execve(WWSYMPA,argv,envp);
}
