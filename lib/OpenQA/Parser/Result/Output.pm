# Copyright (C) 2017 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

package OpenQA::Parser::Result::Output;
# OpenQA test result class - this is how openQA internally draws the output results
# Used while parsing from format X to OpenQA test modules.
use Mojo::Base 'OpenQA::Parser::Result';
use Mojo::File 'path';
has 'file';
has 'content';

sub write {
    my ($self, $dir) = @_;
    path($dir, $self->file)->spurt($self->content);
    $self;
}

1;
