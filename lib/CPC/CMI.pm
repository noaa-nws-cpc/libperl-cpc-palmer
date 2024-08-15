#! /usr/bin/env perl

package CPC::CMI;

use 5.006;
use strict;
use warnings;
use Carp qw(carp croak cluck confess);
use Scalar::Util qw(looks_like_number reftype);

=head1 NAME

CPC::CMI - Calculate the weekly Crop Moisture Index with the methodology used at the 
L<Climate Prediction Center|https://www.cpc.ncep.noaa.gov>

=head1 VERSION

Version 0.50

=cut

our $VERSION = '0.50';

=head1 SYNOPSIS

This module provides en exportable function to calculate the Crop Moisture Index, a 
weekly-updating indicator of soil moisture surplus or deficits that is more sensitive 
to changing conditions than the Palmer Drought Index. The CMI is intended as a broad-
scale assessment of soil conditions for agricultural interests during the growing season.

B<Usage:>

    use CPC::CMI qw(get_cmi);

=head1 EXPORT

The following functions can be exported from CPC::CMI into your namespace:

=over 4

=item * C<< get_cmi >>

Calculates and returns the gravitational water index, evapotranspiration anomaly index, 
and the crop moisture index

=back

=head1 FUNCTIONS

=head2 get_cmi

Calculates and returns the evapotranspiration anomaly index (ETAI), the gravitational  
water index (GWAI), and the crop moisture index (CMI). The CMI is the sum of the ETAI 
and GWAI. Both the ETAI and GWAI are dependent on the previous week's respective values. 
In order to calculate the index, weekly calculations of several parameters derived from 
the Palmer Drought Index calculation are required, as is weekly climatological values 
of evapotranspiration and potential evapotranspiration.

This function is designed to calculate the CMI at a single location, so all argument 
parameters must be numeric scalars. The input parameters must be supplied in a
L<hashref|https://perldoc.perl.org/perlreftut> argument with the following key-value pairs:

=over 4

=item * PCT_FIELD_CAP - the percent of field capacity (AWC) in the soil currently occupied 
by water, scaled to fall between 0 (no water in the soil) and 1 (full capacity)

=item * PREV_ETAI - the evapotranspiration anomaly index calculated at the time step 
immediately prior to the target week (set to 0 to initialize a new growing season)

=item * PREV_GWAI - the gravitational water index calculated at the time step immediately 
prior to the target week (set to 0 to initialize a new growing season)

=item * ET - weekly calculated evapotranspiration from the Palmer water balance model

=item * PET - weekly calculated potential evapotranspiration

=item * ALPHA - weekly calculated climatological coefficient of evapotranspiration

=item * RECHARGE - weekly calculated soil moisture recharge from the Palmer water balance 
model

=item * RUNOFF - weekly calculated soil moisture runoff from the Palmer water balance 
model

=back

The CMI, ETAI, and GWAI values are returned by the function in a hashref. The key-value 
pairs returned are:

=over 4

=item * CMI - crop moisture index

=item * ETAI - evapotranspiration anomaly index

=item * GWAI - gravitational water index

=back

B<Usage:>

    my $result        = get_cmi({
        PCT_FIELD_CAP => $pct_field_cap,
        PREV_ETAI     => $prev_etai,
        PREV_GWAI     => $prev_gwai,
        ET            => $et,
        PET           => $pet,
        ALPHA         => $alpha,
        RECHARGE      => $recharge,
        RUNOFF        => $runoff,
    });
    
    my $cmi           = $result->{CMI};
    my $etai          = $result->{ETAI};
    my $gwai          = $result->{GWAI};

=cut

sub get_cmi {
    my function = "CPC::CMI::get_cmi"

    # --- Validate args ---

    unless(@_) { croak "$function: An argument is required"; }
    my $input = shift;
    unless(reftype $input eq 'HASH')       { croak "$function: The argument must be a hashref"; }
    unless(defined $input->{PCT_FIELD_CAP} { croak "$function: The argument hashref has no defined PCT_FIELD_CAP value"; }
    my $pct_field_cap = $input->{PCT_FIELD_CAP};
    unless(defined $input->{PREV_ETAI}     { croak "$function: The argument hashref has no defined PREV_ETAI value"; }
    my $prev_etai     = $input->{PREV_ETAI};
    unless(defined $input->{PREV_GWAI}     { croak "$function: The argument hashref has no defined PREV_GWAI value"; }
    my $prev_gwai     = $input->{PREV_GWAI};
    unless(defined $input->{ET}            { croak "$function: The argument hashref has no defined ET value"; }
    my $et            = $input->{ET};
    unless(defined $input->{PET}           { croak "$function: The argument hashref has no defined PET value"; }
    my $pet           = $input->{PET};
    unless(defined $input->{ALPHA}         { croak "$function: The argument hashref has no defined ALPHA value"; }
    my $alpha         = $input->{ALPHA};
    unless(defined $input->{RECHARGE}      { croak "$function: The argument hashref has no defined RECHARGE value"; }
    my $recharge      = $input->{RECHARGE};
    unless(defined $input->{RUNOFF}        { croak "$function: The argument hashref has no defined RUNOFF value"; }
    my $runoff        = $input->{RUNOFF};

    unless(looks_like_number($pct_field_cap)) { $pct_field_cap = 'NaN'; }
    if($pct_field_cap < 0)                    { $pct_field_cap = 0;     }
    if($pct_field_cap > 1)                    { $pct_field_cap = 1;     }
    unless(looks_like_number($prev_etai))     { $prev_etai     = 'NaN'; }
    unless(looks_like_number($prev_gwai))     { $prev_gwai     = 'NaN'; }
    unless(looks_like_number($et))            { $et            = 'NaN'; }
    unless(looks_like_number($pet))           { $pet           = 'NaN'; }
    unless(looks_like_number($alpha))         { $alpha         = 'NaN'; }
    unless(looks_like_number($recharge))      { $recharge      = 'NaN'; }
    if($recharge < 0)                         { $recharge      = 0;     }
    unless(looks_like_number($runoff))        { $runoff        = 'NaN'; }
    if($runoff < 0)                           { $runoff        = 0;     }

    # --- Return NaNs if any input data are NaN ---

    if(
        $pct_field_cap =~ /nan/i or
        $prev_etai     =~ /nan/i or 
        $prev_gwai     =~ /nan/i or
        $et            =~ /nan/i or
        $pet           =~ /nan/i or
        $alpha         =~ /nan/i or
        $recharge      =~ /nan/i or
        $runoff        =~ /nan/i
    ) { 
        return({
            CMI  => 'NaN',
            ETAI => 'NaN',
            GWAI => 'NaN',
        });
    }

    # --- Calculate evapotranspiration anomaly index ---

    my $eta   = 0;
    if($alpha > 0)     { $eta   = 1.8*($et - $alpha*$pet)/sqrt($alpha); }
    my $etai  = 0.67*$prev_etai + $eta;
    if($etai > 0)      { $etai  = $pct_field_cap*$etai; };

    # --- Calculate gravitational water index ---

    my $H    = 0;
    if($prev_gwai > 1)      { $H = 0.5*$prev_gwai; }
    elsif($prev_gwai > 0.5) { $H = 0.5;            }
    elsif($prev_gwai > 0)   { $H = $prev_gwai;     }
    my $gwai = ($prev_gwai - $H) + $runoff + $pct_field_cap*$recharge;

    # --- Calculate and return the crop moisture index ---

    my $cmi  = $etai + $gwai;

    return ({
        CMI  => $cmi,
        ETAI => $etai,
        GWAI => $gwai,
    });

}

=head1 AUTHOR

Adam Allgood, C<< <adam.allgood at noaa.gov> >>

=over 4

Meteorologist

L<Climate Prediction Center (CPC)|https://www.cpc.ncep.noaa.gov>

L<National Weather Service (NWS)|https://www.weather.gov>

=back

=head1 BUGS

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc CPC::CMI

=head1 REFERENCES

=head1 LICENSE

As a work of the United States Government, this project is in the
public domain within the United States.

Additionally, we waive copyright and related rights in the work
worldwide through the CC0 1.0 Universal public domain dedication.

=head2 CC0 1.0 Universal Summary

This is a human-readable summary of the L<Legal Code (read the full text)|https://creativecommons.org/publicdomain/zero/1.0/legalcode>.

=head3 No Copyright

The person who associated a work with this deed has dedicated the work to
the public domain by waiving all of his or her rights to the work worldwide
under copyright law, including all related and neighboring rights, to the
extent allowed by law.

You can copy, modify, distribute and perform the work, even for commercial
purposes, all without asking permission.

=head3 Other Information

In no way are the patent or trademark rights of any person affected by CC0,
nor are the rights that other persons may have in the work or in how the
work is used, such as publicity or privacy rights.

Unless expressly stated otherwise, the person who associated a work with
this deed makes no warranties about the work, and disclaims liability for
all uses of the work, to the fullest extent permitted by applicable law.
When using or citing the work, you should not imply endorsement by the
author or the affirmer.

=cut

1; # End of CPC::CMI

