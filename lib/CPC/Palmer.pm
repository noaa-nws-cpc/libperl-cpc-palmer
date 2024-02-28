#! /usr/bin/env perl

package CPC::Palmer;

use 5.006;
use strict;
use warnings;
use Carp qw(carp croak cluck confess);
use Scalar::Util qw(looks_like_number reftype);

=head1 NAME

CPC::Palmer - Calculate the Palmer Drought Index with the modified selection algorithm used
at the L<Climate Prediction Center|https://www.cpc.ncep.noaa.gov>

=head1 VERSION

Version 0.50

=cut

our $VERSION = '0.50';

=head1 SYNOPSIS

This module provides exportable functions to calculate the Palmer Drought Severity Index 
(PDSI) with a modified selection algorithm that is used in Climate Prediction Center (CPC) 
operations. This modified Palmer Index (PMDI) removes the need for backtracking to select 
the final PDSI value once a new dry or wet spell becomes definitively established. When an 
established spell is potentially ending, the PMDI is set to the weighted average of the 
established spell and the opposite (potentially beginning) spell's PDSI values using the 
probability that the established spell has ended.

B<Usage:>

    use CPC::Palmer qw(get_palmer_pmdi);

=head1 EXPORT

The following functions can be exported from CPC::Palmer into your namespace:

=over 4

=item * C<< get_water_balance >>

Calculates and returns the potential and actual Palmer water balance parameters based on a
two-layer model of the soil

=item * C<< get_cafec_precipitation >>

Calculates and returns the climatically appropriate for existing conditions (CAFEC) 
precipitation based on current soil moisture parameters and climatology

=back

=head1 FUNCTIONS

=head2 get_water_balance

Calculates and returns the potential and actual Palmer water balance parameters based on a 
two-layer model of the soil. The total amount of water the soil at a location can store is 
defined as the AWC - the available water capacity. The PDSI procedure divides the soil into 
two layers: a topsoil layer that can hold up to 1 inch of water, and a subsoil layer that 
holds the remaining amount of the AWC. Water is first removed from or added to the topsoil 
layer to meet demand or receive surplus moisture.

This function is designed to calculate the water balance at a single location, so all 
argument parameters must be numeric scalars. The input parameters must be supplied in a 
L<hashref|https://perldoc.perl.org/perlreftut> argument with the following key-value pairs:

=over 4

=item * AWC - the total available water capacity of the soil in inches

=item * PET - the potential evapotranspiration calculated for the target period in inches

=item * PRECIP - the total accumulated precipitation calculated for the target period in 
inches

=item * SM_LOWER - the soil moisture contained in the lower soil layer (subsoil) in inches 
at the start of the target period

=item * SM_UPPER - the soil moisture contained in the upper soil layer (topsoil) in inches 
at the start of the target period

=back

The module L<CPC::PET|https://github.com/noaa-nws-cpc/libperl-cpc-pet> provides functions to 
calculate potential evapotranspiration.

A source for AWC data is the Dunne and Willmott 
(2000) gridded 
L<Global Distribution of Plant-Extractable Water Capacity of Soil|https://daac.ornl.gov/SOILS/guides/Dunne.html> 
available through NASA's Oak Ridge National Laboratory Distributed Active Archive Center.

When initializing the PDSI at the beginning of the data record, the soil moisture content of 
the lower and upper layers, if unknown, can be set to field capacity. Subsequent usage of 
this function can then compute the soil moisture levels for consecutively advancing time 
periods using the soil moisture values returned (see below) as the new soil moisture input 
values.

The water balance parameters returned by the function are also stored in a hashref. The 
key-value pairs returned are:

=over 4

=item * ET - the actual evapotranspiration in inches

=item * PR - the potential recharge in inches

=item * R - the actual recharge in inches

=item * PRO - the potential runoff in inches

=item * RO - the actual runoff in inches

=item * PL - the potential loss in inches

=item * L - the actual loss in inches

=item * SM_LOWER - the soil moisture contained in the lower soil layer (subsoil) in inches 
at the end of the target period

=item * SM_UPPER - the soil moisture contained in the upper soil layer (topsoil) in inches 
at the end of the target period

=back

B<Usage:>

    my $wb_params = get_water_balance({
        AWC      => $awc,
        PET      => $pet,
        PRECIP   => $precip,
        SM_LOWER => $sm_lower,
        SM_UPPER => $sm_upper,
    });
    
    my $evapotranspiration = $wb_params->{ET};
    my $recharge           = $wb_paramd->{R};
    # etc.

=cut

sub get_water_balance {
    my $function = "CPC::Palmer::get_water_balance";

    # --- Validate args ---

    unless(@_) { croak "$function: An argument is required"; }
    my $input = shift;
    unless(reftype $input eq 'HASH')     { croak "$function: The argument must be a hashref"; }
    unless(defined $input->{AWC})        { croak "$function: The argument hashref has no defined AWC value"; }
    my $awc      = $input->{AWC};
    unless(defined $input->{PET})        { croak "$function: The argument hashref has no defined PET value"; }
    my $pet      = $input->{PET};
    unless(defined $input->{PRECIP})     { croak "$function: The argument hashref has no defined PRECIP value"; }
    my $precip   = $input->{PRECIP};
    unless(defined $input->{SM_LOWER})   { croak "$function: The argument hashref has no defined SM_LOWER value"; }
    my $sm_lower = $input->{SM_LOWER};
    unless(defined $input->{SM_UPPER})   { croak "$function: The argument hashref has no defined SM_UPPER value"; }
    my $sm_upper = $input->{SM_UPPER};
    unless(looks_like_number($awc))      { $pet = 'NaN'; }
    unless(looks_like_number($pet))      { $pet = 'NaN'; }
    unless(looks_like_number($precip))   { $pet = 'NaN'; }
    unless(looks_like_number($sm_lower)) { $pet = 'NaN'; }
    unless(looks_like_number($sm_upper)) { $pet = 'NaN'; }
    if($pet < 0)                         { $pet    = 0;  }
    if($precip < 0)                      { $precip = 0;  }

    # --- Return NaNs if any input data are NaN ---

    if(
        $awc =~ /nan/i or
        $pet =~ /nan/i or
        $precip =~ /nan/i or
        $sm_lower =~ /nan/i or
        $sm_upper =~ /nan/i
    ) {
        return({
            ET       => 'NaN',
            PR       => 'NaN',
            R        => 'NaN',
            PRO      => 'NaN',
            RO       => 'NaN',
            PL       => 'NaN',
            L        => 'NaN',
            SM_LOWER => 'NaN',
            SM_UPPER => 'NaN',
        });
    }

    # --- Determine moisture holding capacity of both soil layers ---

    my($sm_lower_cap,$sm_upper_cap);

    if($awc > 1)      {
        $sm_lower_cap = $awc - 1;
        $sm_upper_cap = 1;
    }
    elsif($awc > 0.1) {
        $sm_lower_cap = 0.1;
        $sm_upper_cap = $awc;
    }
    else              {
        $sm_lower_cap = 0.1;
        $sm_upper_cap = 0.1;
    }

    # --- Define output params ---

    my($et,$pr,$r,$pro,$ro,$pl,$l,$sm_lower_final,$sm_upper_final);

    # --- Calculate potential values ---

    $pr  = ($sm_lower_cap + $sm_upper_cap) - ($sm_lower + $sm_upper);
    $pro = ($sm_lower_cap + $sm_upper_cap) - $pr;  # Estimation made by Palmer 1965 that assumes observed precip is still unknown
    my $pl_upper = $pet;
    $pl_upper    = $pl_upper <= $sm_upper ? $pl_upper : $sm_upper;
    my $pl_lower = $sm_lower*($pet - $pl_upper)/($sm_lower_cap + $sm_upper_cap);
    $pl_lower    = $pl_lower <= $sm_lower ? $pl_lower : $sm_lower;
    $pl          = $pl_lower + $pl_upper;

    # --- Calculate actual values ---

    my $surplus = $precip - $pet;

    if($surplus >= 0) { # Precip meets or exceeds demand
        $et             = $pet;
        $l              = 0;
        my $r_upper     = $surplus;
        $r_upper        = $r_upper <= $sm_upper_cap - $sm_upper ? $r_upper : $sm_upper_cap - $sm_upper;
        my $r_lower     = $surplus - $r_upper;
        $r_lower        = $r_lower <= $sm_lower_cap - $sm_lower ? $r_lower : $sm_lower_cap - $sm_lower;
        $r              = $r_lower + $r_upper;
        $ro             = $surplus - $r;
        $ro             = $ro > 0 ? $ro : 0;
        $sm_lower_final = $sm_lower + $r_lower;
        $sm_lower_final = $sm_lower_final < $sm_lower_cap ? $sm_lower_final : $sm_lower_cap;
        $sm_upper_final = $sm_upper + $r_upper;
        $sm_upper_final = $sm_upper_final < $sm_upper_cap ? $sm_upper_final : $sm_upper_cap;
    }
    else              { # Precip did not meet demand
        my $deficit     = abs($surplus);
        $r              = 0;
        $ro             = 0;
        my $l_upper     = $deficit;
        $l_upper        = $l_upper <= $sm_upper ? $l_upper : $sm_upper;
        my $l_lower     = $sm_lower*($deficit - $l_upper)/($sm_lower_cap + $sm_upper_cap);
        $l_lower        = $l_lower <= $sm_lower ? $l_lower : $sm_lower;
        $l              = $l_lower + $l_upper;
        $et             = $precip + $l;
        $sm_lower_final = $sm_lower - $l_lower;
        $sm_lower_final = $sm_lower_final > 0 ? $sm_lower_final : 0;
        $sm_upper_final = $sm_upper - $l_upper;
        $sm_upper_final = $sm_upper_final > 0 ? $sm_upper_final : 0;
    }

    return({
        ET       => $et,
        PR       => $pr,
        R        => $r,
        PRO      => $pro,
        RO       => $ro,
        PL       => $pl,
        L        => $l,
        SM_LOWER => $sm_lower_final,
        SM_UPPER => $sm_upper_final,
    });

}

=head2 get_cafec_precipitation

Calculates and returns the climatically appropriate for existing conditions (CAFEC)
precipitation in inches based on current soil moisture parameters and climatology. In the 
PDSI calculations, the CAFEC precipitation is the precipitation amount that would maintain 
the same PDSI index value through the target time period.

This function is designed to calculate the CAFEC precipitation at a single location, so all
argument parameters must be numeric scalars. The input parameters must be supplied in a
L<hashref|https://perldoc.perl.org/perlreftut> argument with the following key-value pairs:

=over 4

=item * PET - The potential evapotranspiration calculated for the target period in inches

=item * ALPHA - The climatological coefficient of evapotranspiration, which is the average 
evapotranspiration divided by the average potential evapotranspiration for the target period

=item * PR - The potential recharge calculated for the target period in inches

=item * BETA - The climatological coefficient of recharge, which is the average recharge 
divided by the average potential recharge for the target period

=item * PRO - The potential runoff calculated for the target period in inches

=item * GAMMA - The climatological coefficient of runoff, which is the average runoff 
divided by the average potential runoff for the target period

=item * PL - The potential loss calculated for the target period in inches

=item * DELTA - The climatological coefficient of loss, which is the average loss divided by 
the average potential loss for the target period

=back

Potential evapotranspiration must be calculated independently by the user. The module 
L<CPC::PET|https://github.com/noaa-nws-cpc/libperl-cpc-pet> provides functions to calculate 
potential evapotranspiration. The other soil moisture parameters can be calculated from the 
L</get_water_balance> function in this module. A long archive of these soil moisture 
parameters is needed in order to compute the climatological parameters ALPHA, BETA, GAMMA, 
and DELTA.

This function returns the CAFEC precipitation as a numeric scalar value.

B<Usage:>

    my $cafec_precip = get_cafec_precipitation({
        PET   => $pet,
        ALPHA => $et_climo/$pet_climo,
        PR    => $pr,
        BETA  => $r_climo/$pr_climo,
        PRO   => $pro,
        GAMMA => $ro_climo/$pro_climo,
        PL    => $pl,
        DELTA => $l_climo/$pl_climo,
    });

=cut

sub get_cafec_precipitation {

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

    perldoc CPC::Palmer

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

1; # End of CPC::Palmer

