# QueryVINStructure.pl
# Uses the VIN structure database to decode late-model Chrysler VINs
#Modification History
# 13-NOV-2013: GGARIEPY: Created

=head1 Copyright Notice

--------------------------------
Copyright (C)2013 Geoff Gariepy
--------------------------------

=cut

use 5.014;

use Data::Dumper;
use DBI;
use constant {
	FALSE => 0,
	TRUE=> 1,
};

# Launch the DBI SQLite driver (which is itself a Perl SQLite engine implementation)
say "Connecting to VIN structure database";


#Decode_VIN('1D7RV1GT9AS211708');
Decode_VIN('1D7RV1CT2BS516927');
#Decode_VIN('1C6RD7KT9CS341201');

=head2 Connect_To_Database()

Locates the database path on the current machine and returns a
connected DBI database handle

=cut

sub Connect_To_Database {
	my $dbfile;
	if (-e 'C:\\Documents and Settings\\reguser\\My Documents\\Dropbox\\VIN Project\\database\\VINStructure.db') {
		$dbfile = 'C:\\Documents and Settings\\reguser\\My Documents\\Dropbox\\VIN Project\\database\\VINStructure.db';
	}
	elsif (-e 'C:\\Users\\GEGA\\Dropbox\\VIN Project\\database\\VINStructure.db') {
		$dbfile = 'C:\\Users\\GEGA\\Dropbox\\VIN Project\\database\\VINStructure.db';
	}
	else {
		die "Could not locate database!";
	}

	my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile","","");
	return $dbh;
}


=head2 Decode_VIN()

Parses VIN data and outputs decoded information.

=cut

sub Decode_VIN {
	my $vin_input = shift;
	my $details_hash = shift;
	my $debug = TRUE;

	my $vsh = Connect_To_Database();

	my $vindata_by_position = {
		'1'		=>{'description' => 'Country of Origin'},
		'2'		=>{'description' => 'Make'},
		'3'		=>{'description' => 'Vehicle Type'},
		'4'		=>{'description' => 'GVWR'},
		'5'		=>{'description' => 'Model Line and Vehicle Family'},
		'6'		=>{'description' => 'Series/Price Class'},
		'7'		=>{'description' => 'Body Style by Vehicle Line'},
		'8'		=>{'description' => 'Engine'},
		'9'		=>{'description' => 'Check Digit'},
		'10'	=>{'description' => 'Model Year'},
		'11'	=>{'description' => 'Assembly Plant'},
	};

	say "Processing [$vin_input]";
	my @vin_chars = (split(//, $vin_input));

	### Step one: determine VIN check digit is correct
	if (Calculate_Check_Digit($vin_input) == FALSE) {
		say "Bad VIN, check digit does not match data.  Aborting.";
		return;
	}
	else {$debug and say "VIN check digit correct";}


	### Step two: determine vehicle model year
	my $sth = $vsh->prepare('select Year from VIN10 where VIN_Code= ?');
	$sth->execute($vin_chars[9]) || die $vsh->error;
	my $year;
	if (my $results = $sth->fetchrow()) {
		$year = $results;
		$debug and say "Year: $vin_chars[9] = $year";
	}

	### Step three: determine country and manufacturer
     $sth = $vsh->prepare('select description from VIN01 where VIN_Code = ?');
     $sth->execute($vin_chars[0]) || die $vsh->error;
     my $country;
	if (my $results = $sth->fetchrow()) {
		$country = $results;
		$debug and say "Country: $vin_chars[0] = $country";
	}

     $sth = $vsh->prepare('select MFG_Names.MFG_Name from VIN02 inner join MFG_Names on MFG_Names.MFG_ID = VIN02.MFG_ID where VIN02.VIN_Code = ?');
	$sth->execute($vin_chars[1]) || die $vsh->error;
	my $mfg;
	if (my $results = $sth->fetchrow()) {
		$mfg = $results;
		$debug and say "Manufacturer: $vin_chars[1] = $mfg";
	}

	### Step four: determine vehicle class, type, and family
	$sth = $vsh->prepare(<<"VIN5");
select
	Vehicle_Classes.Description as [Vehicle_Class],
	Vehicle_Types.Description as [Vehicle_Type],
     Vehicle_Types.Master_Type as [Master_Type],
	Vehicle_Families.Family_Name_Code as [Vehicle_Family]
from
	VIN05
		inner join Vehicle_Classes on (VIN05.Vehicle_Class_ID = Vehicle_Classes.Class_ID)
		inner join Vehicle_Types on (VIN05.Vehicle_Type_ID = Vehicle_Types.Type_ID)
		inner join Vehicle_Families on (VIN05.Family_ID = Vehicle_Families.Family_ID)
where
	VIN05.VIN_Code = ? and VIN05.Year = ?
	
VIN5

	my $drivetrain = 'UNKNOWN';
     my $vehicle_class;
	my $vehicle_type;
     my $master_type;
     my $trim_level = 'UNKNOWN';
	my $vehicle_family;
	$sth->execute($vin_chars[4], $year) || die $vsh->error;
	if (my $results = $sth->fetchrow_hashref) {
		$vehicle_class = $results->{'Vehicle_Class'};
          $master_type = $results->{'Master_Type'};
		$vehicle_type = $results->{'Vehicle_Type'};
		$vehicle_family =  $results->{'Vehicle_Family'};
          if ($vehicle_type =~ /4x4|AWD/) {
               $drivetrain = '4WD';
          }
          else {
               $drivetrain = '2WD/FWD';
          }
		$debug and say "VIN5: $vin_chars[4] = $vehicle_class, $vehicle_type, $drivetrain, $vehicle_family";
	}

	## There was a design change in the way Chrysler encoded the 
	## vehicle price class, body style, etc., for model year 2012.
	## The following logic determines if the vehicle is pre- or 
	## post-2012 and follows the appropriate path to decode the VIN.

	my $vehicle_price_class;
	my $vehicle_body_style;
	if ($year < 2012) {
		# Determine vehicle price class
		$sth = $vsh->prepare(<<"VIN6");
select
	Vehicle_Job_Price_Classes.Description as [Price_Class]
from
	VIN06
		inner join Vehicle_Job_Price_Classes on (VIN06.Job_Price_Class_ID = Vehicle_Job_Price_Classes.Job_Price_ID)
where
	VIN06.VIN_Code = ? and VIN06.Year = ?
VIN6

		$sth->execute($vin_chars[5], $year) || die $vsh->error;
		if (my $results = $sth->fetchrow_hashref) {
			$vehicle_price_class = $results->{'Price_Class'};
			$debug and say "VIN6: $vin_chars[5] = $vehicle_price_class";
		}
		# Determine vehicle body style from VIN7

          $sth = $vsh->prepare(<<"VIN7");
select
     Description as [Body_Style]
from
     VIN07
where
     Year=? and
     VIN_Code = ? and
     Vehicle_Line = ?
VIN7
          $sth->execute($year, $vin_chars[6], $master_type);
		if (my $results = $sth->fetchrow_hashref) {
			$vehicle_body_style = $results->{'Body_Style'};
			$debug and say "VIN7: $vin_chars[5] = $vehicle_body_style";
		}
	}
	else {
		# VIN 5-6-7 combine to determine Brand, Marketing Name,
		# Drive Wheels, Cab/Body Type, Drive Position and Price Series
		my $vin_codes = $vin_chars[4].$vin_chars[5].$vin_chars[6];
          say "Decoding VIN 5-6-7 [$vin_codes] for model year 2012 and up";
		$sth = $vsh->prepare(<<"VIN567");
SELECT 
	VEHICLE_CLASSES.DESCRIPTION as [Vehicle_Class],
     VEHICLE_JOB_PRICE_CLASSES.DESCRIPTION as [Job_Class],
	VEHICLE_TYPES.DESCRIPTION as [Vehicle_Type],
	VEHICLE_FAMILIES.FAMILY_NAME_CODE as [Vehicle_Family],
	BODY_STYLES.DESCRIPTION as [Body_Style],
	TRIM_LEVELS.TRIM_LEVEL_NAME as [Trim_Level]
FROM
	VIN_COMBO_05_06_07
		INNER JOIN VEHICLE_CLASSES ON (VIN_COMBO_05_06_07.VEHICLE_CLASS_ID = VEHICLE_CLASSES.CLASS_id)
          INNER JOIN VEHICLE_JOB_PRICE_CLASSES ON (VIN_COMBO_05_06_07.[Job_Price_Class_ID] = VEHICLE_JOB_PRICE_CLASSES.[Job_Price_ID])
		INNER JOIN VEHICLE_TYPES ON (VIN_COMBO_05_06_07.VEHICLE_TYPE_ID = VEHICLE_TYPES.TYPE_ID)
		INNER JOIN VEHICLE_FAMILIES ON (VIN_COMBO_05_06_07.FAMILY_ID = VEHICLE_FAMILIES.FAMILY_ID)
		INNER JOIN BODY_STYLES ON (VIN_COMBO_05_06_07.BODY_STYLE_ID = BODY_STYLES.BODY_STYLE_ID)
		INNER JOIN TRIM_LEVELS ON (VIN_COMBO_05_06_07.TRIM_LEVEL_ID = TRIM_LEVELS.TRIM_LEVEL_ID)
WHERE
	YEAR = ? AND
	VIN_CODES = ?
VIN567

          $sth->execute($year,$vin_codes) || die $vsh->error;
		if (my $results = $sth->fetchrow_hashref) {
               $vehicle_class = $results->{'Vehicle_Class'};
               $vehicle_price_class = $results->{'Job_Class'};
               $vehicle_body_style = $results->{'Body_Style'};
               $trim_level = $results->{'Trim_Level'};
               $vehicle_family = $results->{'Vehicle_Family'};
               $vehicle_type = $results->{'Vehicle_Type'};
               if ($vehicle_type =~ /4x4|AWD/) {
                    $drivetrain = '4WD';
               }
               else {
                    $drivetrain = '2WD/FWD';
               }
               say "VIN 5-6-7 ($vin_codes) = ";
               say "\tVehicle Type: $vehicle_type";
               say "\tVehicle Class: $vehicle_class";
               say "\tVehicle Price/Job Class: $vehicle_price_class";
               say "\tVehicle Body Style: $vehicle_body_style";
               say "\tTrim Level: $trim_level";
               say "\tDrive_Train: $drivetrain";
          }
	}

## Step 5: Determine Restraint Types
# Another weird one.  From 2006 through 2009, VIN03 encoded both the 
# vehicle class (MPV, Truck, Car) as well as the restraints installed.
# From 2006 to 2009, VIN04 encoded the vehicle GVRW and theoretically brake types, 
# but all were hydraulic.

# In 2010 on up, VIN03 only encoded vehicle class (MPV, Truck, Car),
# and VIN04 encoded GVRW and theoretical (all hydraulic) brake types, AS
# WELL AS restraint types.  Confused yet?

my $restraint_type;
my $gvwr;
if ($year >= 2006 and $year <= 2008) { # Look only at VIN03 for restraints
     # Need to know vehicle type

}
elsif ($year == 2009) {                 # Look at VIN03 for restraints, but need to know
                                        # vehicle family

}
elsif ($year > 2009) {                  # Look only at VIN04 for restraints
     $sth = $vsh->prepare(<<VIN04A);
select
     GVWR_Types.[Restraint_Type],
     GVWR_Types.GVWR as [GVWR]
from
     VIN04
          inner join GVWR_Types on (VIN04.GVWR_Type = GVWR_Types.Type_ID)
where
     VIN_Code = ? and Year = ?;  
VIN04A
     $sth->execute($vin_chars[3], $year);
     if (my $results = $sth->fetchrow_hashref) {
          $restraint_type = $results->{'Restraint_Type'};
          $gvwr = $results->{'GVWR'};
          $debug and say "VIN4: GVWR for VIN character $vin_chars[3] = $gvwr";
     }
     $sth = $vsh->prepare(<<VIN04B);
select 
       Vehicle_Restraint_Classes.[Description]       
from
       Vehicle_Restraint_Classes       
where
     Vehicle_Restraint_Classes.[Class_ID] = ?  
VIN04B
     $sth->execute($restraint_type);
     if (my $results = $sth->fetchrow()) {
          $restraint_type = $results;
          $debug and say "VIN4: Restraint type for VIN character $vin_chars[3] = $restraint_type";
     }
}

## Step 6: Determine engine

## Step 7: Determine assembly plant
my $assembly_plant;
$sth = $vsh->prepare('select description from VIN11 where VIN_Code = ?');
$sth->execute($vin_chars[10]) || die $vsh->error;
my $country;
if (my $results = $sth->fetchrow()) {
     $assembly_plant = $results;
     $debug and say "Assembly plant: $vin_chars[10] = $assembly_plant";
}


# Final step: determine vehicle serial number
my $vehicle_serial = substr($vin_input, 11);
$debug and say "Vehicle serial number: $vehicle_serial";


#	foreach my $vin_char (@vin_chars) {
#		my $description = $vindata_by_position->{$position}{'description'};
#		my $value;
#		if ($position == 4) {
#			foreach my $key (keys($vindata_by_position->{$position})) {
#				if ($vin_char =~ /$key/) {
#					 $value = $vindata_by_position->{$position}{$key};
#				}
#			}
#		}
#		elsif ($position < 4 or ($position > 7 and $position != 12 and $position != 9)) {
#			$value = $vindata_by_position->{$position}{$vin_char};
#			if ($value eq 'Truck') {
#				$is_truck = TRUE;
#			}
#		}
#		elsif ($position == 5 or $position == 6) {
#			my $href = ($is_truck == TRUE) ? $vindata_by_position->{$position}{'Truck'} :
#											$vindata_by_position->{$position}{'MPV'};
#			$value = $href->{$vin_char};
#			if ($position == 5 and $value =~ /RAM/i) {
#				$is_ram = TRUE;
#			}
#			elsif ($position == 5 and $value =~ /DAK/i) {
#				$is_dak = TRUE;
#			}
#			elsif ($position == 5 and $value !~ /RAM|DAK/) {
#				$is_mpv = TRUE;
#			}
#		}
#		elsif ($position == 7) {
#			my $href;
#			$is_ram and $href = $vindata_by_position->{$position}{'Ram'};
#			$is_dak and $href = $vindata_by_position->{$position}{'Dakota'};
#			$is_mpv and $href = $vindata_by_position->{$position}{'MPV'};
#			$value = $href->{$vin_char};
#		}
#		elsif ($position == 9) {
#			$value = $vin_char;
#		}
#		elsif ($position == 12) {
#			$value = substr($vin_input, 11);
#			$details_hash->{'vin_serial'} = $value;
#			last;
#		}
#		$position++;
#		$details_hash->{'VIN_' . $description} = $value;
#	}
	return;
}


=head2 Calculate_Check_Digit()

Computes a standard VIN check digit from the VIN, 
and matches it up to the check digit in the 9th position.

Returns TRUE if the check digit is correct, FALSE otherwise.

=cut

sub Calculate_Check_Digit {
	my $vin_input = shift;

	my $transliterate = {
							'A' => 1, 'B' => 2, 'C' => 3,
							'D' => 4, 'E' => 5, 'F' => 6,
							'G' => 7, 'H' => 8, 'J' => 1,
							'K' => 2, 'L' => 3, 'M' => 4,
							'N' => 5, 'P' => 7, 'R' => 9,
							'S' => 2, 'T' => 3, 'U' => 4,
							'V' => 5, 'W' => 6, 'X' => 7,
							'Y' => 8, 'Z' => 9};

	my @weights = qw(8 7 6 5 4 3 2 10 0 9 8 7 6 5 4 3 2);

	my @vin_chars = (split(//, $vin_input));

	my $vin_check_digit = $vin_chars[8];

	my $weightpos = 0;
	my $sum = 0;

	foreach my $char (@vin_chars) {
		my $val;
		if ($char =~ /[0-9]/) {$val = $char;}
		else {$val = $transliterate->{$char};}
		$sum += $val * $weights[$weightpos++];
	}

	my $calc_check_digit = $sum % 11;

	if ($calc_check_digit == 10) {$calc_check_digit = 'X';}

	if ($calc_check_digit eq $vin_check_digit) {
		return TRUE;
	}
	return FALSE;
}