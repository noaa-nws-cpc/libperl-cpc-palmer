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

=item * C<< get_moisture_departure >>

Calculates and returns the moisture departure, which is the difference between the
precipitation received during the target period and the CAFEC precipitation

=item * C<< get_z_index >>

Calculates and returns the Palmer Z-index, which is the Palmer moisture departure parameter
scaled by a location specific climatic coefficient (K) term in order to be comparable across
different locations and time periods

=item * C<< get_palmer_accountings >>

Calculates and returns the three PDSI spell accounting terms, accumulated effective wetness
(or dryness) to end an established spell, and the probability that an established spell has
ended

=item * C<< get_palmer_pmdi >>

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
    unless(looks_like_number($awc))      { $awc      = 'NaN'; }
    unless(looks_like_number($pet))      { $pet      = 'NaN'; }
    unless(looks_like_number($precip))   { $precip   = 'NaN'; }
    unless(looks_like_number($sm_lower)) { $sm_lower = 'NaN'; }
    unless(looks_like_number($sm_upper)) { $sm_upper = 'NaN'; }
    if($pet < 0)                         { $pet      = 0;     }
    if($precip < 0)                      { $precip   = 0;     }

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
    my $function = "CPC::Palmer::get_cafec_precipitation";

    # --- Validate args ---

    unless(@_) { croak "$function: An argument is required"; }
    my $input = shift;
    unless(reftype $input eq 'HASH') { croak "$function: The argument must be a hashref"; }
    unless(defined $input->{PET})    { croak "$function: The argument hashref has no defined PET value"; }
    my $pet   = $input->{PET};
    unless(defined $input->{ALPHA})  { croak "$function: The argument hashref has no defined ALPHA value"; }
    my $alpha = $input->{ALPHA};
    unless(defined $input->{PR})     { croak "$function: The argument hashref has no defined PR value"; }
    my $pr    = $input->{PR};
    unless(defined $input->{BETA})   { croak "$function: The argument hashref has no defined BETA value"; }
    my $beta  = $input->{BETA};
    unless(defined $input->{PRO})    { croak "$function: The argument hashref has no defined PRO value"; }
    my $pro   = $input->{PRO};
    unless(defined $input->{GAMMA})  { croak "$function: The argument hashref has no defined GAMMA value"; }
    my $gamma = $input->{GAMMA};
    unless(defined $input->{PL})     { croak "$function: The argument hashref has no defined PL value"; }
    my $pl    = $input->{PL};
    unless(defined $input->{DELTA})  { croak "$function: The argument hashref has no defined DELTA value"; }
    my $delta = $input->{DELTA};
    unless(looks_like_number($pet))   { $pet   = 'NaN'; }
    unless(looks_like_number($alpha)) { $alpha = 'NaN'; }
    unless(looks_like_number($pr))    { $pr    = 'NaN'; }
    unless(looks_like_number($beta))  { $beta  = 'NaN'; }
    unless(looks_like_number($pro))   { $pro   = 'NaN'; }
    unless(looks_like_number($gamma)) { $gamma = 'NaN'; }
    unless(looks_like_number($pl))    { $pl    = 'NaN'; }
    unless(looks_like_number($delta)) { $delta = 'NaN'; }

    # --- Return NaN if any input data are NaN ---

    if(
        $pet   =~ /nan/i or
        $alpha =~ /nan/i or
        $pr    =~ /nan/i or
        $beta  =~ /nan/i or
        $pro   =~ /nan/i or
        $gamma =~ /nan/i or
        $pl    =~ /nan/i or
        $delta =~ /nan/i
    ) { return 'NaN'; }

    # --- Calculate and return CAFEC precipitation ---

    return $alpha*$pet + $beta*$pr + $gamma*$pro - $delta*$pl;
}

=head2 get_moisture_departure

Calculates and returns the Palmer moisture departure, which is the difference between the 
precipitation received during the target period and the CAFEC precipitation. Positive values 
cause a positive change in the Z-Index, while negative values cause a negative change in the 
Z-Index.

This function is designed to calculate the moisture departure at a single location, so all
argument parameters must be numeric scalars. The input parameters must be supplied in a
L<hashref|https://perldoc.perl.org/perlreftut> argument with the following key-value pairs:

=over 4

=item * PRECIP - the total accumulated precipitation calculated for the target period in 
inches

=item * CAFEC_PRECIP - the climatologically appropriate for existing conditions precipitation 
in inches

=back

The CAFEC precipitation can be calculated using the L</get_cafec_precipitation> function in 
this module.

This function returns the moisture departure as a numeric scalar value.

B<Usage:>

    my $D = get_moisture_departure({
        PRECIP       => $precip,
        CAFEC_PRECIP => $cafec_precip,
    });

=cut

sub get_moisture_departure {
    my $function = "CPC::Palmer::get_moisture_departure";

    # --- Validate args ---

    unless(@_) { croak "$function: An argument is required"; }
    my $input = shift;
    unless(reftype $input eq 'HASH')         { croak "$function: The argument must be a hashref"; }
    unless(defined $input->{PRECIP})         { croak "$function: The argument hashref has no defined PRECIP value"; }
    my $precip       = $input->{PRECIP};
    unless(defined $input->{CAFEC_PRECIP})   { croak "$function: The argument hashref has no defined CAFEC_PRECIP value"; }
    my $cafec_precip = $input->{CAFEC_PRECIP};
    unless(looks_like_number($precip))       { $precip       = 'NaN'; }
    unless(looks_like_number($cafec_precip)) { $cafec_precip = 'NaN'; }

    # --- Return NaN if any input data are NaN ---

    if(
        $precip       =~ /nan/i or
        $cafec_precip =~ /nan/i
    ) { return 'NaN'; }

    # --- Calculate and return the moisture departure ---

    return $precip - $cafec_precip;
}

=head2 get_z_index

Calculates and returns the Palmer Z-index, which is the Palmer moisture departure parameter 
scaled by a location specific climatic coefficient (K) term in order to be comparable across 
different locations and time periods.

This function is designed to calculate the Palmer Z-Index at a single location, so all
argument parameters must be numeric scalars. The input parameters must be supplied in a
L<hashref|https://perldoc.perl.org/perlreftut> argument with the following key-value pairs:

=over 4

=item * D - the moisture anomaly parameter

=item * K - the climatic characteristic value for the target location and time period

=back

The climatic characteristic (K)  must be calculated independently by the user. The module
L<CPC::Palmer::Climatology|https://github.com/noaa-nws-cpc/libperl-cpc-palmer> provides 
a function to calculate the climatic characteristic. Long record climatologies of the 
L<soil moisture parameters|/get_water_balance> are required to compute K. The moisture 
departure term can be calculated from the L</get_moisture_departure> function in this module.

This function returns the Palmer Z-index as a numeric scalar value.

B<Usage:>

    my $Z_index = get_z_index({
        D => $D,
        K => $K,
    });

=cut

sub get_z_index {
    my $function = "CPC::Palmer::get_z_index";

    # --- Validate args ---

    unless(@_) { croak "$function: An argument is required"; }
    my $input = shift;
    unless(reftype $input eq 'HASH') { croak "$function: The argument must be a hashref"; }
    unless(defined $input->{D})      { croak "$function: The argument hashref has no defined D value"; }
    my $d     = $input->{D};
    unless(defined $input->{K})      { croak "$function: The argument hashref has no defined K value"; }
    my $K     = $input->{K};
    unless(looks_like_number($d))    { $d = 'NaN'; }
    unless(looks_like_number($K))    { $K = 'NaN'; }

    # --- Return NaN if any input data are NaN ---

    if(
        $d =~ /nan/i or
        $K =~ /nan/i
    ) { return 'NaN'; }

    # --- Calculate and return the moisture departure ---

    return $d*$K;
}

=head2 get_palmer_accountings

Calculates and returns the three PDSI spell accounting terms, accumulated effective wetness 
(or dryness) to end an established spell, and the probability that an established spell has 
ended. The Palmer Drought Index itself is a weighted sum of the target period's Z-index value 
and the previous Palmer Drought Index. In order to define whether a drought or wet spell has 
begun or has ended, the PDSI procedure maintains three separate accountings of the Palmer 
Drought Index. These are:

=over 4

=item * X1 - Severity index for a wet spell that is potentially becoming established

=item * X2 - Severity index for a dry spell that is potentially becoming established

=item * X3 - Severity index for a spell (either wet or dry) that is definitively established

=back

Additional information is required to determine whether an established spell has ended, 
therefore allowing one of the potentially establishing spells to become the new definitively 
established spell if the magnitide of the index is sufficient. This is:

=over 4

=item * PROB_SPELL_END - The "probability" that an established spell has ended as calculated 
in Palmer 1965

=item * UACCUM - The effective wetness (or dryness) to definitively end the established spell 
that has accumulated since PROB_SPELL_END became non-zero

=back

This function requires two arguments. The first argument must be a string defining the time 
period for which the PDSI is being calculated. The length of the time period determines the 
value of the duration factors used to compute the severity index. Supported time periods 
include (case-insensitive):

=over 4

=item * WEEK - A weekly PDSI (used in CPC operations)

=item * MONTH - The original Palmer time period

=item * PENTAD - A 5-day PDSI (used by UC Merced)

=back

The second argument is a L<hashref|https://perldoc.perl.org/perlreftut> containing the input 
parameters needed to calculate the PDSI accountings. This function is designed to calculate 
the PDSI accounting parameters at a single location, so all argument parameters must be 
numeric scalars. The following key-value pairs are needed:

=over 4

=item * X1 - the "X1" PDSI value for the time period immediately prior to the target period

=item * X2 - the "X2" PDSI value for the time period immediately prior to the target period

=item * X3 - the "X3" PDSI value for the time period immediately prior to the target period

=item * UACCUM - the accumulated effective wetness (or dryness) to definitively end an 
established spell

=back

This function returns the PDSI accounting parameters for the target period as a hashref with 
the following parameters:

=over 4

=item * X1 - the "X1" PDSI value for the target period

=item * X2 - the "X2" PDSI value for the target period

=item * X3 - the "X3" PDSI value for the target period

=item * UACCUM - the accumulated effective wetness (or dryness) to definitively end an
established spell

=item * PROB_SPELL_END - the probability that the established spell has ended

=back

Since the PDSI is an iterative index, these returned parameters can be supplied to the 
function in order to calculate the subsequent time period's PDSI accounting parameters.

B<Usage:>

    my $pdsi = get_palmer_accountings('week',{
        X1     => $pdsi_x1,
        X2     => $pdsi_x2,
        X3     => $pdsi_x3,
        UACCUM => $uaccum,
    });
    
    $pdsi_x1        = $pdsi->{X1};
    $pdsi_x2        = $pdsi->{X2};
    $pdsi_x3        = $pdsi->{X3};
    $uaccum         = $pdsi->{UACCUM};
    $prob_spell_end = $pdsi->{PROB_SPELL_END};

=cut

sub get_palmer_accountings {
    my $function = "CPC::Palmer::get_palmer_accountings";

    # --- Validate args ---

    unless(@_ >= 2) { croak "$function: Two arguments are required"; }
    my $period = shift;

    unless($period =~ /week/i or $period =~ /month/i or $period =~ /pentad/i) {
        croak "$function: $period is an unsupported time period type";
    }

    my $input = shift;
    unless(reftype $input eq 'HASH') { croak "$function: The second argument must be a hashref"; }
    unless(defined $input->{Z_INDEX}){ croak "$function: The second argument hashref has no defined Z_INDEX value"; }
    my $z_index     = $input->{Z_INDEX};
    unless(defined $input->{X1})     { croak "$function: The second argument hashref has no defined X1 value"; }
    my $prev_x1     = $input->{X1};
    unless(defined $input->{X2})     { croak "$function: The second argument hashref has no defined X2 value"; }
    my $prev_x2     = $input->{X2};
    unless(defined $input->{X3})     { croak "$function: The second argument hashref has no defined X3 value"; }
    my $prev_x3     = $input->{X3};
    unless(defined $input->{UACCUM}) { croak "$function: The second argument hashref has no defined UACCUM value"; }
    my $prev_uaccum = $input->{UACCUM};
    unless(looks_like_number($z_index))     { $z_index     = 'NaN'; }
    unless(looks_like_number($prev_x1))     { $prev_x1     = 'NaN'; }
    unless(looks_like_number($prev_x2))     { $prev_x2     = 'NaN'; }
    unless(looks_like_number($prev_x3))     { $prev_x3     = 'NaN'; }
    unless(looks_like_number($prev_uaccum)) { $prev_uaccum = 'NaN'; }

    if(
        $z_index     =~ /nan/i or
        $prev_x1     =~ /nan/i or
        $prev_x2     =~ /nan/i or
        $prev_x3     =~ /nan/i or
        $prev_uaccum =~ /nan/i
    ) { return({
        X1             => 'NaN',
        X2             => 'NaN',
        X3             => 'NaN',
        UACCUM         => 'NaN',
        PROB_SPELL_END => 'NaN',
        });
    }

    if($prev_x1 < 0)        { $prev_x1 = 0; }
    if($prev_x2 > 0)        { $prev_x2 = 0; }
    if(abs($prev_x3) < 0.5) { $prev_x3 = 0; $prev_uaccum = 0; }
    if($prev_x3 > 0 and $prev_uaccum > 0) { $prev_uaccum = 0; }
    if($prev_x3 < 0 and $prev_uaccum < 0) { $prev_uaccum = 0; }

    # --- Set duration factors based on time period ---

    my($df,$zewt);

    if($period =~ /week/i)     {
        $df   = 0.975;
        $zewt = -2.925;
    }
    elsif($period =~ /month/i) {
        $df   = 0.897;
        $zewt = -2.691;
    }
    else                       { # Pentad
        $df   = 0.9828;
        $zewt = -2.925;  # THIS NEEDS TO BE UPDATED
    }

    # --- Parameters to calculate ---

    my($x1,$x2,$x3,$uaccum,$prob_spell_end);

    # --- Calculate the Palmer accountings ---

    if(abs($prev_x3) <= 0.5) {  # No active spell is established
        $x1               = $df*$prev_x1 + $z_index/3.0;
        if($x1 < 0) { $x1 = 0; }
        $x2               = $df*$prev_x2 + $z_index/3.0;
        if($x2 > 0) { $x2 = 0; }
        $uaccum           = 0;
        $prob_spell_end   = 0;
        $x3               = &_check_for_new_spell($x1,$x2);
        &_return_palmer_accountings($x1,$x2,$x3,$uaccum,$prob_spell_end);
    }
    else                     {  # Active spell
        $x3     = $df*$prev_x3 + $z_index/3.0;

        # --- Check if the spell has ended ---

        if(abs($x3) <= 0.5) {  # Spell is definitively ended
            $x1               = $df*$prev_x1 + $z_index/3.0;
            if($x1 < 0) { $x1 = 0; }
            $x2               = $df*$prev_x2 + $z_index/3.0;
            if($x2 > 0) { $x2 = 0; }
            $uaccum           = 0;
            $prob_spell_end   = 1;
            $x3               = &_check_for_new_spell($x1,$x2);
            &_return_palmer_accountings($x1,$x2,$x3,$uaccum,$prob_spell_end);
        }

        my $u;
        my $z_effective;

        if($x3 > 0) {  # Wet spell
            $z_effective = $zewt*$prev_x3 + 1.5;

            if($z_index <= $z_effective) {  # Spell is ended
                $x1               = $df*$prev_x1 + $z_index/3.0;
                if($x1 < 0) { $x1 = 0; }
                $x2               = $df*$prev_x2 + $z_index/3.0;
                if($x2 > 0) { $x2 = 0; }
                $uaccum           = 0;
                $prob_spell_end   = 1;
                $x3               = &_check_for_new_spell($x1,$x2);
                &_return_palmer_accountings($x1,$x2,$x3,$uaccum,$prob_spell_end);
            }

            $u = $z_index - 0.15;
        }
        else        {  # Dry spell
            $z_effective = $zewt*$prev_x3 - 1.5;

            if($z_index >= $z_effective) {  # Spell is ended
                $x1               = $df*$prev_x1 + $z_index/3.0;
                if($x1 < 0) { $x1 = 0; }
                $x2               = $df*$prev_x2 + $z_index/3.0;
                if($x2 > 0) { $x2 = 0; }
                $uaccum           = 0;
                $prob_spell_end   = 1;
                $x3               = &_check_for_new_spell($x1,$x2);
                &_return_palmer_accountings($x1,$x2,$x3,$uaccum,$prob_spell_end);
            }

            $u = $z_index + 0.15;
        }

        if($prev_uaccum != 0) {  # Tracking a potentially ending spell
            $uaccum         = $prev_uaccum + $u;
            if(($z_effective + $prev_uaccum) == 0) { $prev_uaccum += 0.00001; }
            $prob_spell_end = $uaccum/($z_effective + $prev_uaccum);
            if($prob_spell_end > 0.999) { $prob_spell_end = 1; }
            if($prob_spell_end < 0.001) { $prob_spell_end = 0; }

            if($prob_spell_end == 1) {  # Spell is ended
                $x1               = $df*$prev_x1 + $z_index/3.0;
                if($x1 < 0) { $x1 = 0; }
                $x2               = $df*$prev_x2 + $z_index/3.0;
                if($x2 > 0) { $x2 = 0; }
                $uaccum           = 0;
                $x3               = &_check_for_new_spell($x1,$x2);
                &_return_palmer_accountings($x1,$x2,$x3,$uaccum,$prob_spell_end);
            }
            elsif($prob_spell_end == 0) {  # Spell is firmly re-established
                $x1     = 0;
                $x2     = 0;
                $uaccum = 0;
                &_return_palmer_accountings($x1,$x2,$x3,$uaccum,$prob_spell_end);
            }
            else {
                $x1               = $df*$prev_x1 + $z_index/3.0;
                if($x1 < 0) { $x1 = 0; }
                $x2               = $df*$prev_x2 + $z_index/3.0;
                if($x2 > 0) { $x2 = 0; }
                &_return_palmer_accountings($x1,$x2,$x3,$uaccum,$prob_spell_end);
            }

        }
        else                  {  # Spell was previously firmly established

            if($x3 > 0) {  # Wet spell
                if($z_index < 0.15)  { $uaccum = $z_index - 0.15; }
                else                 { $uaccum = 0;               }
            }
            else        {  # Dry spell
                if($z_index > -0.15) { $uaccum = $z_index + 0.15; }
                else                 { $uaccum = 0;               }
            }

            if($z_effective == 0) { $z_effective += 0.00001; }
            $prob_spell_end = $uaccum/$z_effective;
            if($prob_spell_end > 0.999) { $prob_spell_end = 1; }
            if($prob_spell_end < 0.001) { $prob_spell_end = 0; }

            if($prob_spell_end == 1)   {  # Spell ended
                $x1               = $df*$prev_x1 + $z_index/3.0;
                if($x1 < 0) { $x1 = 0; }
                $x2               = $df*$prev_x2 + $z_index/3.0;
                if($x2 > 0) { $x2 = 0; }
                $uaccum           = 0;
                $x3               = &_check_for_new_spell($x1,$x2);
                &_return_palmer_accountings($x1,$x2,$x3,$uaccum,$prob_spell_end);
            }
            elsif($prob_spell_end == 0) {  # Spell firmly established
                $x1     = 0;
                $x2     = 0;
                $uaccum = 0;
                &_return_palmer_accountings($x1,$x2,$x3,$uaccum,$prob_spell_end);
            }
            else                        {
                $x1               = $df*$prev_x1 + $z_index/3.0;
                if($x1 < 0) { $x1 = 0; }
                $x2               = $df*$prev_x2 + $z_index/3.0;
                if($x2 > 0) { $x2 = 0; }
                &_return_palmer_accountings($x1,$x2,$x3,$uaccum,$prob_spell_end);
            }

        }

    }

}

# The next two functions are non-exported, used by &get_palmer_accountings for repetitive 
# codes.

sub _check_for_new_spell {
    my $x1 = shift;
    my $x2 = shift;
    my $x3 = undef;

    if(abs($x1) >= 1 and abs($x2) >=1) { # Rare case of competing spells starting
        $x3 = abs($x1) >= abs($x2) ? $x1 : $x2;
    }
    elsif(abs($x1) >= 1)               {  # Wet spell starting
        $x3 = $x1;
    }
    elsif(abs($x2) >= 1)               {  # Dry spell starting
        $x3 = $x2;
    }
    else                               {  # No spell starting
        $x3 = 0;
    }

    return $x3;
}

sub _return_palmer_accountings {
    my $x1             = shift;
    my $x2             = shift;
    my $x3             = shift;
    my $uaccum         = shift;
    my $prob_spell_end = shift;

    return({
        X1             => $x1,
        X2             => $x2,
        X3             => $x3,
        UACCUM         => $uaccum,
        PROB_SPELL_END => $prob_spell_end,
    });

}

=head2 get_palmer_pmdi

Calculates and returns the Palmer Modified Drought Index (PMDI), a modified selection 
algorithm from the original technique described in Palmer (1965) and Alley (1984) that 
removes the need for backtracking. When an established spell is potentially ending, the 
PMDI is calculated as the weighted average of the established spell and the opposite spell, 
with the probability of the established spell ending set as the weighting factor.

This function is designed to calculate the PMDI at a single location, so all argument 
parameters must be numeric scalars. The input parameters must be supplied in a
L<hashref|https://perldoc.perl.org/perlreftut> argument with the following key-value pairs:

=over 4

=item * X1 - PDSI parameter for a potentially establishing wet spell (>= 0)

=item * X2 - PDSI parameter for a potentially establishing dry spell (<= 0)

=item * X3 - PDSI parameter for a definitively established wet or dry spell

=item * PROB_SPELL_END - the "probability" that a definitively established spell is ending

=back

The input parameters can be calculated by the L</get_palmer_accountings> function in this 
module.

This function returns the PMDI as a numeric scalar value.

B<Usage:>

    my $pmdi = get_palmer_pmdi({
        X1             => $x1,
        X2             => $x2,
        X3             => $x3,
        PROB_SPELL_END => $prob_spell_end,
    });

=cut

sub get_palmer_pmdi {
    my $function = "CPC::Palmer::get_palmer_pmdi";

    # --- Validate args ---

    unless(@_) { croak "$function: An argument is required"; }
    my $input = shift;
    unless(reftype $input eq 'HASH')           { croak "$function: The argument must be a hashref"; }
    unless(defined $input->{X1})               { croak "$function: The argument hashref has no defined X1 value"; }
    my $x1             = $input->{X1};
    unless(defined $input->{X2})               { croak "$function: The argument hashref has no defined X2 value"; }
    my $x2             = $input->{X2};
    unless(defined $input->{X3})               { croak "$function: The argument hashref has no defined X3 value"; }
    my $x3             = $input->{X3};
    unless(defined $input->{PROB_SPELL_END})   { croak "$function: The argument hashref has no defined PROB_SPELL_END value"; }
    my $prob_spell_end = $input->{PROB_SPELL_END};
    unless(looks_like_number($x1))             { $x1             = 'NaN'; }
    unless(looks_like_number($x2))             { $x2             = 'NaN'; }
    unless(looks_like_number($x3))             { $x3             = 'NaN'; }
    unless(looks_like_number($prob_spell_end)) { $prob_spell_end = 'NaN'; }

    # --- Return NaN if any input data are NaN ---

    if(
        $x1             =~ /nan/i or
        $x2             =~ /nan/i or
        $x3             =~ /nan/i or
        $prob_spell_end =~ /nan/i
    ) { return 'NaN'; }

    # --- Calculate and return the PMDI ---

    if(abs($x3) <= 0.5) {  # No established spell
        return abs($x1) >= abs($x2) ? $x1 : $x2;
    }
    elsif($x3 > 0)      {  # Established wet spell
        return (1 - $prob_spell_end)*$x3 + ($prob_spell_end)*$x2;
    }
    else                {  # Established dry spell
        return (1 - $prob_spell_end)*$x3 + ($prob_spell_end)*$x1;
    }

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

