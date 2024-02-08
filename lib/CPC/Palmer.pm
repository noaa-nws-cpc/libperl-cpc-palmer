package CPC::Palmer;

use 5.006;
use strict;
use warnings;
use Carp qw(carp croak cluck confess);
use List::Util qw(all);
use Scalar::Util qw(looks_like_number reftype);

=head1 NAME

CPC::Palmer - Calculate the Palmer Drought Index with the modified selection algorithm used 
at the L<Climate Predicton Center|https://www.cpc.ncep.noaa.gov>.

=head1 VERSION

Version 0.50

=cut

our $VERSION = '0.50';

=head1 SYNOPSIS

This module provides an object-oriented interface to calculate the Palmer Drought Index 
with a modified selection algorithm used in Climate Prediction Center operations. This 
modified Palmer Index (PMDI) removes the need for backtracking to select the final Palmer 
Drought Severity Index value based on whether a dry or wet spell is definitively established.

=head3 Basic Usage

    use CPC::Palmer;
    
    ...
    
    my $palmer = CPC::Palmer->new($awc);
    $palmer->set_params(\%params);

=head1 FUNCTIONS

=head2 new

This is the constructor method for the CPC::Palmer module. The method requires one argument, 
the total available water capacity (AWC) of the soil for the location(s) where the Palmer 
Drought Index will be calculated. Multiple locations can be provided by supplying them in an 
array reference. Non-numeric AWC values will be converted to 'NaN's. The method returns a 
CPC::Palmer object - a reference blessed into the CPC::Palmer class.

When subsequent parameters are supplied to the CPC::Palmer object using the L</"set_params"> 
method, those args will be checked to make sure their dimensions match the AWC argument 
provided here.

B<Usage:>

    my $palmer_one_location   = CPC::Palmer->new($awc);  # Scalar argument
    my $palmer_many_locations = CPC::Palmer->new(\@awc); # Array ref argument

=cut

sub new {
    my $class = shift;
    my $self  = {};

    # --- Set up object data structure ---

    # Static params

    $self->{CLASS}    = $class;
    $self->{AWC}      = undef;
    $self->{SIZE}     = undef;
    $self->{RETURN}   = undef;

    # Climo params

    $self->{ALPHA}    = undef;
    $self->{BETA}     = undef;
    $self->{GAMMA}    = undef;
    $self->{DELTA}    = undef;
    $self->{KCHAR}    = undef;

    # Palmer params

    $self->{PET}      = undef;
    $self->{PRECIP}   = undef;
    $self->{SM_LOWER} = undef;
    $self->{SM_UPPER} = undef;
    $self->{X1}       = undef;
    $self->{X2}       = undef;
    $self->{X3}       = undef;
    $self->{UACCUM}   = undef;

    # --- Get arg ---

    unless(@_ >= 1) { croak "$class\::new - An argument is required"; }
    my $awc    = shift;

    if(defined reftype($awc) and reftype($awc) eq 'ARRAY') {
        $self->{AWC}    = $awc;
        $self->{SIZE}   = scalar(@{$awc});
        $self->{RETURN} = 'ARRAY';
    }
    elsif(looks_like_number($awc)) {
        $self->{AWC}    = [$awc];
        $self->{SIZE}   = 1;
        $self->{RETURN} = 'SCALAR';
    }
    else {
        croak "$class\::new - Invalid argument - must be a numeric SCALAR or an ARRAY ref";
    }

    # --- Validate arg ---

    my $non_numeric = 0;

    for(my $i=0; $i<$self->{SIZE}; $i++) {

        unless(looks_like_number($$self->{AWC}[$i])) {
            $$self->{AWC}[$i] = 'NaN';
            $non_numeric++;
        }

    }

    if($non_numeric) { carp "$class\::new - Found $non_numeric non-numeric AWC values - set them to NaN"; }

    bless($self,$class);
    return $self;
}

=head2 set_params

This method provides an interface for the user to supply data parameters required for 
calculating the Palmer Drought Index to the CPC::Palmer object. Supplied parameters will 
be validated to make sure they match the dimensions of the object's AWC parameter (supplied 
as an argument when the object was created with L</"new">). Non-numeric values will be set 
to 'NaN's.

Parameters (i.e., key/value pairs in the hash ref arg) that do not match any keys in the 
object data will be ignored. This method will not check if all of the object parameters have 
been successfully supplied. The methods that calculate the components of the Palmer Index 
(such as L</"calculate_palmer_index"> or L</"calculate_water_balance">) will validate the 
data parameters they require.

B<Usage:>

    $palmer->set_params(\%params);

=cut

sub set_params {
    my $self   = shift;
    my $class  = $self->{CLASS};
    my $method = "$class\:set_params";
}

=head2 calculate_palmer_index

=cut

sub calculate_palmer_index {
    my $self   = shift;
    my $class  = $self->{CLASS};
    my $method = "$class\::calculate_palmer_index";
}

=head2 calculate_water_balance

=cut

sub calculate_water_balance {
    my $self   = shift;
    my $class  = $self->{CLASS};
    my $method = "$class\::calculate_water_balance";
}

=head2 calculate_cafec_precip

=cut

sub calculate_cafec_precip {
    my $self   = shift;
    my $class  = $self->{CLASS};
    my $method = "$class\::calculate_cafec_precip";
}

=head2 calculate_z_index

=cut

sub calculate_z_index {
    my $self   = shift;
    my $class  = $self->{CLASS};
    my $method = "$class\::calculate_z_index";
}

=head2 calculate_palmer_accountings

=cut

sub calculate_palmer_accountings {
    my $self   = shift;
    my $class  = $self->{CLASS};
    my $method = "$class\::calculate_palmer_accountings";
}

=head2 calculate_palmer_pmdi

=cut

sub calculate_palmer_pmdi {
    my $self   = shift;
    my $class  = $self->{CLASS};
    my $method = "$class\::calculate_palmer_pmdi";
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

Thornthwaite, C. W., 1948: An approach toward a rational classification of climate. I<Geographical Review>, B<38> 55-94.

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
