#!perl
use 5.014;

use constant {
    FALSE => 0,
    TRUE  => 1,
};

my $restraint_types = {
    '[A-F]'   =>  'Active Belts (A.S.P.), Front Air Bags (O.S.P.), No Side Air Bags',
    '[G-M]'   =>  'Active Belts (A.S.P.), Front Air Bags (O.S.P.), Side Air Bags Front Row',
    '[N-U]'   =>  'Active Belts (A.S.P.), Front Air Bags (O.S.P.), Side Air Bags All Rows',
    '[VXYZ1-2]' => 'Active Belts (A.S.P.), No Air Bags',
    '[3-6]'   =>  'Active Belts (A.S.P.), Trucks over 10,000lbs GVWR',
    'W'       =>  'Incomplete Vehicles With Hydraulic Brakes',
};
    

my $vindata_by_position = {
	'1'		=>  {
	                'description' => 'Country of Origin',
					'1'	=> 'U.S.',
					'2'	=> 'Canada',
					'3'	=> 'Mexico',
				},
    '2'     =>  {
                    'description' => 'Make',
                    'A' => 'Chrysler',
                    'B' => 'Dodge',
                    'D' => 'Dodge',
                    'C' => 'Ram',
                    'J' => 'Jeep',
                },
    '3'     =>  {
                    'description' => 'Vehicle Type',
                    '3' => 'Truck',
                    '4' => 'Multipurpose Passenger Vehicle',
                    '5' => 'Truck',
                    '6' => 'Incomplete Vehicle',
                    '7' => 'Truck',
                    '8' => 'Multipurpose Passenger Vehicle',
                },
    '4'     =>  {
                    'description' => 'GVWR',
                    'A|G|N|V'  => 'GVWR = 4001-5000#',
                    'B|H|P|X'  => 'GVWR = 5001-6000#',
                    'C|J|R|Y'  => 'GVWR = 6001-7000#',
                    'D|K|S|Z'  => 'GVWR = 7001-8000#',
                    'E|L|T|1'  => 'GVWR = 8001-9000#',
                    'F|M|U|2'  => 'GVWR = 9001-10000#',
                    '3'        => 'GVWR = 10001-14000#',
                    '4'        => 'GVWR = 14001-16000#',
                    '5'        => 'GVWR = 16001-19500#',
                    '6'        => 'GVWR = 19501-26000#',
                    'W'        => 'Incomplete Vehicle, GVRW Determined by downstream manufacturer',
                },
    '5'     =>  {
                    'description' => 'Model Line and Vehicle Family',
                    'Truck' => {
                                '3' => 'Ram Chassis Cab (4x4) "DX" Family',
                                '5' => 'Ram Pickup Light Duty (4x2) "DX" Family',
                                '6' => 'Ram Pickup Light Duty (4x4) "DX" Family',
                                'U' => 'Ram Pickup Light Duty (4x4) "DR" Family',
                                'B' => 'Ram Pickup Light Duty (4x2) "DS" Family',
                                'C' => 'Ram Chassis Cab (4x2) "DM" Family',
                                'D' => 'Ram Chassis Cab (4x4) "DM" Family',
                                'E' => 'Dakota 4x2 "ND" Family',
                                'G' => 'Ram Chassis Cab (4x2) "DC" Family',
                                'H' => 'Ram Chassis Cab (4x4) "DC" Family',
                                'L' => 'Ram Pickup Heavy Duty (4x2) "D1" Family',
                                'N' => 'Ram Chassis Cab (4x2) "DX" Family',
                                'R' => 'Ram Pickup Heavy Duty (4x2) "DH" Family',
                                'S' => 'Ram Pickup Heavy Duty (4x4) "DH" Family',
                                'V' => 'Ram Pickup Light Duty (4x4) "DS" Family',
                                'W' => 'Dakota 4x4 "ND" Family',
                                'X' => 'Ram Pickup Heavy Duty (4x4) "D1" Family',
                                },
                    'MPV' => {
                                'G' => 'Journey Left Hand Drive, Front Wheel Drive "JC" Family',
                                'H' => 'Journey Left Hand Drive, All Wheel Drive "JC" Family',
                                '5' => 'Journey Right Hand Drive, Front Wheel Drive "JC" Family',
                                'T' => 'Nitro Left Hand Drive, 4x2 "KA" Family',
                                'U' => 'Nitro Left Hand Drive, 4x4 "KA" Family',
                                '9' => 'Nitro Right Hand Drive, 4x4 "KA" Family',
                                'R' => 'Town & Country Left Hand Drive, Front Wheel Drive "RT" Family',
                                'S' => 'Grand Voyager Left Hand Drive, Front Wheel Drive "RT" Family',
                                'T' => 'Grand Voyager Right Hand Drive, Front Wheel Drive "RT" Family',
                                'S' => 'Grand Voyager Left Hand Drive, Front Wheel Drive "RT" Family',
                                },
                },
    '6'     =>  {
                    'description' => 'Series/Price Class',
                    'Truck' => {
                                '1' => '1500',
                                '2' => '2500', 
                                '3' => '3500 Less DRW',
                                '4' => '3500 DRW',
                                '5' => '4000 DWR',
                                '6' => '4500 DWR',
                                '7' => '5500 DWR',
                                },
                    'MPV' => {
                                '1' => 'E (Economy)',    
                                '2' => 'L (Low Line)', 
                                '3' => 'M (Medium)',   
                                '4' => 'H (High Line)',
                                '5' => 'P (Premium)',              
                                '6' => 'S (Sport)',                
                                '7' => 'X (Special)',
                                },
                },
     '7'    =>  {
                    'description' => 'Body Style by Vehicle Line',
                    'Dakota' => 
                                {
                                    '2' => 'Extended Cab / Dakota Pickup',
                                    'B' => 'Extended Cab / Dakota Pickup',
                                    'G' => 'Crew Cab / Dakota Pickup',
                                    '8' => 'Crew Cab / Dakota Pickup',
                                },
                    'Ram' =>
                                {
                                    '3' => 'Crew Cab',
                                    'C' => 'Crew Cab',
                                    '8' => 'Quad Cab',
                                    'G' => 'Quad Cab',
                                    '6' => 'Regular Cab/Chassis', 
                                    'E' => 'Regular Cab/Chassis', 
                                    'H' => 'Mega Cab',
                                },
                    'MPV'       =>
                                {
                                    '1' => 'Extended Van Grand Caravan C/V',
                                    '4' => 'Extended Van Grand Caravan, Voyager T&C',
                                    'A' => 'Extended Van Grand Caravan C/V',
                                    '7' => 'Hatchback Tall / Journey Body Style',
                                    'F' => 'Hatchback Tall / Journey Body Style',
                                    'G' => 'Sport Utility 4 Door',
                                    '8' => 'Sport Utility 4 Door',
                                    'D' => 'Extended Wagon,Grand Caravan/Voyager T&C',
                                },
                },
      '8'   =>  {
           'description' => 'Engine',
           '2' => '5.7L 8CYL Mul Disp Gasoline (EZB)',
           'C' => '1.8L 4CYL Gasoline Non-Turbo (EBA)',
           'Y' => '2.0L 4CYL Diesel  (ECD, ECE)',
           'A' => '2.0L 4CYL Gasoline Non-Turbo (ECN, ECP)',
           'A' => '2.0L 4CYL Gaoline/CNG Non-Turbo (ECQ)',
           'U' => '2.2L 4CYL Diesel (ENE)',
           'B' => '2.4L 4CYL Gasoline Non-Turbo (EDG, ED3)',
           'F' => '2.4L 4CYL Gasoline Turbo (ED4)',
           'D' => '2.7L 5CYL Gasoline Non-Turbo (EER)',
           '5' => '2.8L 4CYL Diesel (ENS)',
           'M' => '3.0L 6CYL Diesel (EXL)',
           'E' => '3.3L 6CYL Gasoline Non-Turbo (EGV)',
           'V' => '3.5L 6CYL Gasoline Non-Turbo (EGF, EGG)',
           'K' => '3.7L 6CYL Gasoline Non-Turbo (EKG)',
           'K' => '3.7L 6CYL Gasoline/CNG Non-Turbo (EKH)',
           '1' => '3.8L 6CYL Gasoline Non-Turbo (EGL, EGT)',
           'X' => '4.0L 6CYL Gasoline Non-Turbo (EGQ, EGS)',
           'P' => '4.7L 8CYL Gasoline Non-Turbo (EVE)',
           'T' => '5.7L 8CYL Gasoline Non-Turbo (EZC, EZE, EZH)',
           'W' => '6.1L 8CYL Gasoline Non-Turbo (ESF)',
           'J' => '6.4L 8CYL Gasoline (ESG, ESH)',
           'L' => '6.7L 6CYL Diesel (ETJ)',
           'Z' => '8.4L 10CYL Gasoline Non-Turbo (EWE)',
           },
      '9'  =>  {
               'description' => 'Check Digit',
               },
      '10' =>  {
               'description' => 'Model Year',
               'Y' => '2000', '8' => '2008', 'G' => '2016', 'R' => '2024', 
               '1' => '2001', '9' => '2009', 'H' => '2017', 'S' => '2025', 
               '2' => '2002', 'A' => '2010', 'J' => '2018', 'T' => '2026', 
               '3' => '2003', 'B' => '2011', 'K' => '2019', 'V' => '2027', 
               '4' => '2004', 'C' => '2012', 'L' => '2020', 'W' => '2028', 
               '5' => '2005', 'D' => '2013', 'M' => '2021', 'X' => '2029', 
               '6' => '2006', 'E' => '2014', 'N' => '2022',  
               '7' => '2007', 'F' => '2015', 'P' => '2023'},
      '11' =>  {
               'description' => 'Assembly Plant',
               'A'  => 'Chrysler Technical Center Pre-Production & Pilot',
               'C'  => 'Jefferson North Assembly',
               'D'  => 'Belvidere Assembly',
               'E'  => 'Saltillo Van/Truck Assembly Plant',
               'G'  => 'Saltillo Truck Assembly Plant',
               'H'  => 'Brampton Assembly',
               'J'  => 'St. Louis Assembly North',
               'L'  => 'Toledo South Assembly',
               'N'  => 'Sterling Heights Assembly',
               'R'  => 'Windsor Assembly',
               'S'  => 'Warren Truck Assembly',
               'T'  => 'Toluca Assembly',
               'W'  => 'Toledo North Assembly',
               },
};
             
system('cls');
say 'Ram Truck VIN Decoder';
say 'Researched and built by Geoff Gariepy';
say 'Last update: 24-OCT-2013';

print 'Enter the VIN to decode (Model year 2000 and later) >';
my $vin_input;
while (length($vin_input) != 17) {
    $vin_input = <STDIN>;
    chomp($vin_input);
    $vin_input = uc($vin_input);
    if ($vin_input =~ /[ioq]/i) {
        $vin_input = '';
        say "The letters I, O, and Q are not legal characters in a VIN";
        print "Invalid VIN, please try again >";
    }
    elsif (Calculate_Check_Digit($vin_input) == FALSE) {
        $vin_input = '';
        say "The VIN check digit is incorrect.";
        print "Invalid VIN, please try again >";
    }
}

say "Decoding [$vin_input]\n\n";
my @vin_chars = (split(//, $vin_input));
my $position = 1;
my $serial_number;
my $is_truck = FALSE;
my $is_ram = FALSE;
my $is_dak = FALSE;
my $is_mpv = FALSE;

foreach my $vin_char (@vin_chars) {
    my $description = $position . ": " . $vindata_by_position->{$position}{'description'};
    my $value;
    if ($position == 4) {
        foreach my $key (keys(%$vindata_by_position->{$position})) {
            if ($vin_char =~ /$key/) {
                $value = $vindata_by_position->{$position}{$key};
            }
        }
        foreach my $key (keys(%$restraint_types)) {
            if ($vin_char =~ /$key/) {
                $value .= "\n" . sprintf "%-40s | %-30s", '4: Restraints:', $restraint_types->{$key};
            }
        }
    }
    elsif ($position < 4 or ($position > 7 and $position != 12 and $position != 9)) {
        $value = $vindata_by_position->{$position}{$vin_char};
        if ($value eq 'Truck') {
            $is_truck = TRUE;
        }
    }
    elsif ($position == 5 or $position == 6) {
        my $href = ($is_truck == TRUE) ? $vindata_by_position->{$position}{'Truck'} :
                                         $vindata_by_position->{$position}{'MPV'};
        $value = $href->{$vin_char};
        if ($position == 5 and $value =~ /RAM/i) {
            $is_ram = TRUE;
        }
        elsif ($position == 5 and $value =~ /DAK/i) {
            $is_dak = TRUE;
        }
        elsif ($position == 5 and $value !~ /RAM|DAK/) {
            $is_mpv = TRUE;
        }
    }
    elsif ($position == 7) {
        my $href;
        $is_ram and $href = $vindata_by_position->{$position}{'Ram'};
        $is_dak and $href = $vindata_by_position->{$position}{'Dakota'};
        $is_mpv and $href = $vindata_by_position->{$position}{'MPV'};
        $value = $href->{$vin_char};
    }
    elsif ($position == 9) {
        $value = $vin_char;
    }
    elsif ($position == 12) {
        $value = substr($vin_input, 11);
        printf "%-40s | %-30s\n\n", '12-17: Serial number', $value;
        last;
    }
    $position++;
    printf "%-40s | %-30s\n", $description, $value;
}  

say "Glossary:";
say "A.S.P. = All Seating Positions";
say "O.S.P. = Outboard Seating Positions";

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
