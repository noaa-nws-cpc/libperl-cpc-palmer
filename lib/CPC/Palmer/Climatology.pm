#! /usr/bin/env perl

package CPC::Palmer::Climatology;

use 5.006;
use strict;
use warnings;
use Carp qw(carp croak cluck confess);
use Scalar::Util qw(looks_like_number reftype);

=head1 NAME

CPC::Palmer::Climatology - Functions to help calculate the climatological components of the 
Palmer Drought Severity Index (PDSI)

=head1 VERSION

Version 0.50

=cut

our $VERSION = '0.50';

=head1 SYNOPSIS

This module provides exportable functions to calculate the more complex climatological 
parameters required to calculate the Palmer Drought Severity Index (PDSI), including the 
the CAFEC (climatologically appropriate for existing conditions) coefficients used to compute 
the CAFEC precipitation and the climatic coefficient (K) term used to compute the Z-Index.

B<Usage:>

    use CPC::Palmer::Climatology qw(get_cafec_coeff get_k_coeff);

=head1 EXPORT

The following functions can be exported from CPC::Palmer into your namespace:

=over 4

=item * C<< get_cafec_coeff >>

Given the mean potential and actual values of a water balance parameter, returns the 
CAFEC coefficient value

=item * C<< get_k_coeff >>

Calculates the climatic coefficient (K) term using climatological inputs

=back

=head1 FUNCTIONS

=head2 get_cafec_coeff

Given the mean potential and actual values of a water balance parameter, returns the
CAFEC coefficient value. Water balance parameters include evapotranspiration, recharge, 
runoff, and loss. The coefficient of evapotranspiration is labeled "alpha" in Palmer 1965, 
the coefficient of recharge is "beta", the coefficient of runoff is "gamma", and the 
coefficient of loss is "delta".

The calculation of alpha, beta, gamma, and delta is simply the mean (climatological) actual 
value divided by the mean potential value for a given time period in a year, and should have 
a value ranging from 0 to 1. If the calculated value is below 0, it will be set to 0, and 
if it is greater than 1, it will be set to 1.

This function is designed to calculate the CAFEC coefficient for one location at a time.

B<Usage:>

    # Example showing computing climos and passing to the function
    use List::Util qw(sum);  # Not a required package to use the function, but needed for this example
    ...
    my(@pet,@et);
    my $nyears = 2024 - 1950;
    for(my $year=1950; $year<2024; $year++) { # Loop years in a climatological record
        push(@pet,$pet{$year});  # Pretend our PET values were stored in this hash
        push(@et,$et{$year});
    }
    my $mean_pet = sum(@pet)/$nyears;
    my $mean_et  = sum(@et)/$nyears;
    my $alpha    = get_cafec_coeff($mean_et,$mean_pet);

=cut

sub get_cafec_coeff {
    my $function = "CPC::Palmer::Climatology::get_cafec_coeff";

    # --- Validate args ---

    unless(@_ >= 2) { croak "$function: Two arguments are required"; }
    my $actual    = shift;
    my $potential = shift;
    unless(looks_like_number($actual))    { $actual    = 'NaN'; }
    unless(looks_like_number($potential)) { $potential = 'NaN'; }

    # --- Calculate and return the CAFEC coefficient ---

    my $cafec_coeff = 'NaN';
    if($potential == 0) { $cafec_coeff = 0;                  }
    else                { $cafec_coeff = $actual/$potential; }
    $cafec_coeff    = $cafec_coeff > 0 ? $cafec_coeff : 0;
    $cafec_coeff    = $cafec_coeff < 1 ? $cafec_coeff : 1;
    return $cafec_coeff;
}

=head2 get_k_coeff

This function calculates the climatic coefficient (K) term using climatological inputs. The 
climatic coefficient is used to scale the moisture departure term so that it is comparable 
across space and time. The moisture departure scaled by the climatic coefficient is called 
the Z-Index.

In order to compute the climatic characteristic, the following mean (climatological) 
parameters are required to be passed as arguments I<for every time period of the year>, e.g., 
52 (or 53) values for a weekly PDSI, or 12 values for a monthly PDSI. Therefore, each 
argument should be an L<array ref|https://perldoc.perl.org/perlref> of the correct size.

=over 4

=item * PE - mean potential evapotranspiration

=item * R - mean recharge

=item * RO - mean runoff

=item * L - mean loss

=item * P - mean accumulated precipitation

=item * D - mean I<absolute value of the> moisture departure

=back

The climatic coefficient (K) term for every time period of the year will be returned as an 
array ref. This function is designed to calculate the K coefficients for one location at a 
time.

B<Usage:>

    my $K_Coeff = get_k_coeff($PE,$R,$RO,$L,$P,$D);
    for(my $t=0; $t<@$K_Coeff; $t++) { print "The K-Coeff for time period $t is: ".$$K_Coeff[$t]."\n"; }

=cut

sub get_k_coeff {
    my $function = "CPC::Palmer::Climatology::get_k_coeff";

    # --- Validate args ---

    unless(@_ >= 6) { croak "$function: 6 arguments are required"; }
    my $PE = shift;
    my $R  = shift;
    my $RO = shift;
    my $L  = shift;
    my $P  = shift;
    my $D  = shift;
    unless(
        reftype $PE eq 'ARRAY' and
        reftype $R  eq 'ARRAY' and
        reftype $RO eq 'ARRAY' and
        reftype $L  eq 'ARRAY' and
        reftype $P  eq 'ARRAY' and
        reftype $D  eq 'ARRAY'
    ) { croak "$function: All arguments must be ARRAY refs"; }
    my $nperiods = scalar(@$PE);
    unless(
        scalar(@$R)  == $nperiods and
        scalar(@$RO) == $nperiods and
        scalar(@$L)  == $nperiods and
        scalar(@$P)  == $nperiods and
        scalar(@$D)  == $nperiods
    ) { croak "$function: Arguments have mismatched array sizes"; }

    # --- Calculate K' for each time period ---

    my @K_PRIME;

    for(my $i=0; $i<$nperiods; $i++) {

        if($$P[$i] + $$L[$i] == 0) { push(@K_PRIME,0); }
        else                       {
            my $T       = ($$PE[$i] + $$R[$i] + $$RO[$i])/($$P + $$L);
            my $k_prime = 0.5 + 1.5*log(($T + 2.8)/$$D[$i])/log(10);
            push(@K_PRIME,$k_prime);
        }

    }

    # --- Calculate the K coefficient for each time period ---

    my $denom = 0;
    for(my $j=0; $j<$nperiods; $j++) { $denom += $$D[$j]*$K_PRIME[$j]; }

    my $K_COEFF = [];

    for(my $i=0; $i<$nperiods; $i++) {
        if($denom == 0) { push(@$K_COEFF,0); }
        else            { push(@$K_COEFF,17.67*$K_PRIME[$i]/$denom); }
    }

    return $K_COEFF;
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

