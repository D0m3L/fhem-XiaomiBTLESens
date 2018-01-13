###############################################################################
# 
# Developed with Kate
#
#  (c) 2016-2017 Copyright: Marko Oldenburg (leongaultier at gmail dot com)
#  All rights reserved
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#
# $Id$
#
###############################################################################



#$cmd = "qx(gatttool -i $hci -b $mac --char-write-req -a 0x33 -n A01F";
#$cmd = "qx(gatttool -i $hci -b $mac --char-read -a 0x35";   # Sensor Daten
#$cmd = "qx(gatttool -i $hci -b $mac --char-read -a 0x38";   # Firmware und Batterie
#  e8 00 00 58 0f 00 00 34 f1 02 02 3c 00 fb 34 9b
        
        
        
        


package main;

use strict;
use warnings;
use POSIX;

use JSON;
use Blocking;


my $version = "1.99.37";




my %XiaomiModels = (
        flowerSens      => {'rdata' => '0x35'  ,'wdata' => '0x33'  ,'wdataValue' => 'A01F' ,'battery' => '0x38' ,'firmware' => '0x38'},
        thermoHygroSens => {'wdata' => '0x10'  ,'wdataValue' => '0100' ,'battery' => '0x18' ,'firmware' => '0x24' ,'devicename' => '0x3'},
    );

my %CallBatteryAge = (  '8h'    => 28800,
                                '16h'   => 57600,
                                '24h'   => 86400,
                                '32h'   => 115200,
                                '40h'   => 144000,
                                '48h'   => 172800
    );


# Declare functions
sub XiaomiBTLESens_Initialize($);
sub XiaomiBTLESens_Define($$);
sub XiaomiBTLESens_Undef($$);
sub XiaomiBTLESens_Attr(@);
sub XiaomiBTLESens_stateRequest($);
sub XiaomiBTLESens_stateRequestTimer($);
sub XiaomiBTLESens_Set($$@);
sub XiaomiBTLESens_Get($$@);
sub XiaomiBTLESens_Notify($$);

sub XiaomiBTLESens_ReadBattery($);
sub XiaomiBTLESens_ReadFirmware($);
sub XiaomiBTLESens_ReadSensData($);
sub XiaomiBTLESens_ReadDeviceName($);
sub XiaomiBTLESens_WriteDeviceName($$);
sub XiaomiBTLESens_WriteSensData($);

sub XiaomiBTLESens_ExecGatttool_Run($);
sub XiaomiBTLESens_ExecGatttool_Done($);
sub XiaomiBTLESens_ExecGatttool_Aborted($);
sub XiaomiBTLESens_ProcessingNotification($@);
sub XiaomiBTLESens_WriteReadings($$);
sub XiaomiBTLESens_ProcessingErrors($$);
sub XiaomiBTLESens_encodeJSON($);

sub XiaomiBTLESens_CallBattery_IsUpdateTimeAgeToOld($$);
sub XiaomiBTLESens_CallBattery_Timestamp($);
sub XiaomiBTLESens_CallBattery_UpdateTimeAge($);
sub XiaomiBTLESens_CreateDevicenameHEX($);

sub XiaomiBTLESens_FlowerSensHandle0x35($$);
sub XiaomiBTLESens_FlowerSensHandle0x38($$);
sub XiaomiBTLESens_ThermoHygroSensHandle0x18($$);
sub XiaomiBTLESens_ThermoHygroSensHandle0x10($$);
sub XiaomiBTLESens_ThermoHygroSensHandle0x24($$);







sub XiaomiBTLESens_Initialize($) {

    my ($hash) = @_;

    $hash->{SetFn}      = "XiaomiBTLESens_Set";
    $hash->{GetFn}      = "XiaomiBTLESens_Get";
    $hash->{DefFn}      = "XiaomiBTLESens_Define";
    $hash->{NotifyFn}   = "XiaomiBTLESens_Notify";
    $hash->{UndefFn}    = "XiaomiBTLESens_Undef";
    $hash->{AttrFn}     = "XiaomiBTLESens_Attr";
    $hash->{AttrList}   = "interval ".
                            "disable:1 ".
                            "disabledForIntervals ".
                            "hciDevice:hci0,hci1,hci2 ".
                            "batteryFirmwareAge:8h,16h,24h,32h,40h,48h ".
                            "minFertility ".
                            "maxFertility ".
                            "minTemp ".
                            "maxTemp ".
                            "minMoisture ".
                            "maxMoisture ".
                            "minLux ".
                            "maxLux ".
                            "sshHost ".
                            "model:flowerSens,thermoHygroSens ".
                            "blockingCallLoglevel:2,3,4,5 ".
                            $readingFnAttributes;



    foreach my $d(sort keys %{$modules{XiaomiBTLESens}{defptr}}) {
        my $hash = $modules{XiaomiBTLESens}{defptr}{$d};
        $hash->{VERSION} 	= $version;
    }
}

sub XiaomiBTLESens_Define($$) {

    my ( $hash, $def ) = @_;
    my @a = split( "[ \t][ \t]*", $def );
    
    return "too few parameters: define <name> XiaomiBTLESens <BTMAC>" if( @a != 3 );
    

    my $name                                = $a[0];
    my $mac                                 = $a[2];
    
    $hash->{BTMAC}                          = $mac;
    $hash->{VERSION}                        = $version;
    $hash->{INTERVAL}                       = 300;
    $hash->{helper}{CallSensDataCounter}    = 0;
    $hash->{helper}{CallBattery}    = 0;
    $hash->{NOTIFYDEV}                      = "global";
    $hash->{loglevel}                       = 4;
        
    
    readingsSingleUpdate($hash,"state","initialized", 0);
    $attr{$name}{room}          = "XiaomiBTLESens" if( !defined($attr{$name}{room}) );
    
    Log3 $name, 3, "XiaomiBTLESens ($name) - defined with BTMAC $hash->{BTMAC}";
    
    $modules{XiaomiBTLESens}{defptr}{$hash->{BTMAC}} = $hash;
    return undef;
}

sub XiaomiBTLESens_Undef($$) {

    my ( $hash, $arg ) = @_;
    
    my $mac = $hash->{BTMAC};
    my $name = $hash->{NAME};
    
    
    RemoveInternalTimer($hash);
    BlockingKill($hash->{helper}{RUNNING_PID}) if(defined($hash->{helper}{RUNNING_PID}));
    
    delete($modules{XiaomiBTLESens}{defptr}{$mac});
    Log3 $name, 3, "Sub XiaomiBTLESens_Undef ($name) - delete device $name";
    return undef;
}

sub XiaomiBTLESens_Attr(@) {

    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash                                = $defs{$name};


    if( $attrName eq "disable" ) {
        if( $cmd eq "set" and $attrVal eq "1" ) {
            RemoveInternalTimer($hash);
            readingsSingleUpdate ( $hash, "state", "disabled", 1 );
            Log3 $name, 3, "XiaomiBTLESens ($name) - disabled";
        }

        elsif( $cmd eq "del" ) {
            Log3 $name, 3, "XiaomiBTLESens ($name) - enabled";
        }
    }
    
    elsif( $attrName eq "disabledForIntervals" ) {
        if( $cmd eq "set" ) {
            return "check disabledForIntervals Syntax HH:MM-HH:MM or 'HH:MM-HH:MM HH:MM-HH:MM ...'"
            unless($attrVal =~ /^((\d{2}:\d{2})-(\d{2}:\d{2})\s?)+$/);
            Log3 $name, 3, "XiaomiBTLESens ($name) - disabledForIntervals";
            readingsSingleUpdate ( $hash, "state", "disabled", 1 );
        }
	
        elsif( $cmd eq "del" ) {
            Log3 $name, 3, "XiaomiBTLESens ($name) - enabled";
            readingsSingleUpdate ( $hash, "state", "active", 1 );
        }
    }
    
    elsif( $attrName eq "interval" ) {
        if( $cmd eq "set" ) {
            if( $attrVal < 300 ) {
                Log3 $name, 3, "XiaomiBTLESens ($name) - interval too small, please use something >= 300 (sec), default is 3600 (sec)";
                return "interval too small, please use something >= 300 (sec), default is 3600 (sec)";
            } else {
                $hash->{INTERVAL} = $attrVal;
                Log3 $name, 3, "XiaomiBTLESens ($name) - set interval to $attrVal";
            }
        }

        elsif( $cmd eq "del" ) {
            $hash->{INTERVAL} = 300;
            Log3 $name, 3, "XiaomiBTLESens ($name) - set interval to default";
        }
    }
    
    elsif( $attrName eq "blockingCallLoglevel" ) {
        if( $cmd eq "set" ) {
            $hash->{loglevel} = $attrVal;
            Log3 $name, 3, "XiaomiBTLESens ($name) - set blockingCallLoglevel to $attrVal";
        }

        elsif( $cmd eq "del" ) {
            $hash->{loglevel} = 4;
            Log3 $name, 3, "XiaomiBTLESens ($name) - set blockingCallLoglevel to default";
        }
    }
    
    return undef;
}

sub XiaomiBTLESens_Notify($$) {

    my ($hash,$dev) = @_;
    my $name = $hash->{NAME};
    return if (IsDisabled($name));
    
    my $devname = $dev->{NAME};
    my $devtype = $dev->{TYPE};
    my $events = deviceEvents($dev,1);
    return if (!$events);


    XiaomiBTLESens_stateRequestTimer($hash) if( (grep /^DEFINED.$name$/,@{$events}
                                                    or grep /^INITIALIZED$/,@{$events}
                                                    or grep /^MODIFIED.$name$/,@{$events}
                                                    or grep /^DELETEATTR.$name.disable$/,@{$events}
                                                    or grep /^ATTR.$name.disable.0$/,@{$events}
                                                    or grep /^DELETEATTR.$name.interval$/,@{$events}
                                                    or grep /^DELETEATTR.$name.model$/,@{$events}
                                                    or grep /^ATTR.$name.model.+/,@{$events}
                                                    or grep /^ATTR.$name.interval.[0-9]+/,@{$events} ) and $init_done );
    return;
}

sub XiaomiBTLESens_stateRequest($) {

    my ($hash)      = @_;
    my $name        = $hash->{NAME};
    my %readings;
    
    
    if( AttrVal($name,'model','none') eq 'none') {
        readingsSingleUpdate($hash,"state","set attribute model first",1);
        
    } elsif( !IsDisabled($name) ) {
        if( ReadingsVal($name,'firmware','none') ne 'none' ) {

            return XiaomiBTLESens_ReadBattery($hash)
            if( XiaomiBTLESens_CallBattery_IsUpdateTimeAgeToOld($hash,$CallBatteryAge{AttrVal($name,'BatteryFirmwareAge','24h')}) );

            if( $hash->{helper}{CallSensDataCounter} < 1 ) {
                XiaomiBTLESens_WriteSensData($hash);
                $hash->{helper}{CallSensDataCounter} = $hash->{helper}{CallSensDataCounter} + 1;
                
            } else {
                $readings{'lastGattError'} = 'charWrite faild';
                XiaomiBTLESens_WriteReadings($hash,\%readings);
                $hash->{helper}{CallSensDataCounter} = 0;
                return;
            }
            
        } else {
        
            XiaomiBTLESens_ReadFirmware($hash);
            InternalTimer( gettimeofday() + 120, "XiaomiBTLESens_ReadDeviceName", $hash ) if( AttrVal($name,'model','thermoHygroSens') eq 'thermoHygroSens' );
        }
        
        readingsSingleUpdate($hash,"state","fetch sensor data",1);
    } else {
        readingsSingleUpdate($hash,"state","disabled",1);
    }
}

sub XiaomiBTLESens_stateRequestTimer($) {

    my ($hash)      = @_;
    
    my $name        = $hash->{NAME};

    
    RemoveInternalTimer($hash);
    
    if( $init_done and not IsDisabled($name) ) {
        
        XiaomiBTLESens_stateRequest($hash);
        
    } else {
        readingsSingleUpdate ( $hash, "state", "disabled", 1 );
    }
    
    InternalTimer( gettimeofday()+$hash->{INTERVAL}+int(rand(600)), "XiaomiBTLESens_stateRequestTimer", $hash );
    
    Log3 $name, 4, "XiaomiBTLESens ($name) - stateRequestTimer: Call Request Timer";
}

sub XiaomiBTLESens_ReadBattery($) {

    my $hash        = shift;
    
    my $name        = $hash->{NAME};
    my $mac         = $hash->{BTMAC};


    $hash->{helper}{RUNNING_PID} = BlockingCall("XiaomiBTLESens_ExecGatttool_Run", $name."|".$mac."|read|".$XiaomiModels{$attr{$name}{model}}{battery}, "XiaomiBTLESens_ExecGatttool_Done", 60, "XiaomiBTLESens_ExecGatttool_Aborted", $hash) unless(exists($hash->{helper}{RUNNING_PID}));
    
    Log3 $name, 4, "XiaomiBTLESens ($name) - CallBattery: call function ExecGatttool_Run";
}

sub XiaomiBTLESens_ReadFirmware($) {

    my $hash        = shift;
    
    my $name        = $hash->{NAME};
    my $mac         = $hash->{BTMAC};


    $hash->{helper}{RUNNING_PID} = BlockingCall("XiaomiBTLESens_ExecGatttool_Run", $name."|".$mac."|read|".$XiaomiModels{$attr{$name}{model}}{firmware}, "XiaomiBTLESens_ExecGatttool_Done", 60, "XiaomiBTLESens_ExecGatttool_Aborted", $hash) unless(exists($hash->{helper}{RUNNING_PID}));
    
    Log3 $name, 4, "XiaomiBTLESens ($name) - CallFirmware: call function ExecGatttool_Run";
}

sub XiaomiBTLESens_ReadDeviceName($) {

    my $hash        = shift;
    
    my $name        = $hash->{NAME};
    my $mac         = $hash->{BTMAC};


    $hash->{helper}{RUNNING_PID} = BlockingCall("XiaomiBTLESens_ExecGatttool_Run", $name."|".$mac."|read|".$XiaomiModels{$attr{$name}{model}}{devicename}, "XiaomiBTLESens_ExecGatttool_Done", 60, "XiaomiBTLESens_ExecGatttool_Aborted", $hash) unless(exists($hash->{helper}{RUNNING_PID}));
    
    Log3 $name, 4, "XiaomiBTLESens ($name) - CallDeviceName: call function ExecGatttool_Run";
}

sub XiaomiBTLESens_ReadSensData($) {

    my $hash        = shift;
    
    my $name        = $hash->{NAME};
    my $mac         = $hash->{BTMAC};

    
    $hash->{helper}{RUNNING_PID} = BlockingCall("XiaomiBTLESens_ExecGatttool_Run", $name."|".$mac."|read|".$XiaomiModels{$attr{$name}{model}}{rdata}, "XiaomiBTLESens_ExecGatttool_Done", 60, "XiaomiBTLESens_ExecGatttool_Aborted", $hash) unless(exists($hash->{helper}{RUNNING_PID}));
    
    Log3 $name, 4, "XiaomiBTLESens ($name) - CallSensData: call function ExecGatttool_Run";
}

sub XiaomiBTLESens_WriteSensData($) {

    my $hash        = shift;
    
    my $name        = $hash->{NAME};
    my $mac         = $hash->{BTMAC};


    $hash->{helper}{RUNNING_PID} = BlockingCall("XiaomiBTLESens_ExecGatttool_Run", $name."|".$mac."|write|".$XiaomiModels{$attr{$name}{model}}{wdata}."|".$XiaomiModels{$attr{$name}{model}}{wdataValue}, "XiaomiBTLESens_ExecGatttool_Done", 60, "XiaomiBTLESens_ExecGatttool_Aborted", $hash) unless(exists($hash->{helper}{RUNNING_PID}));
    
    Log3 $name, 4, "XiaomiBTLESens ($name) - WriteSensData: call function ExecGatttool_Run";
}

sub XiaomiBTLESens_WriteDeviceName($$) {

    my ($hash,$value)   = @_;
    
    my $name            = $hash->{NAME};
    my $mac             = $hash->{BTMAC};


    $hash->{helper}{RUNNING_PID} = BlockingCall("XiaomiBTLESens_ExecGatttool_Run", $name."|".$mac."|write|".$XiaomiModels{$attr{$name}{model}}{devicename}."|".$value, "XiaomiBTLESens_ExecGatttool_Done", 60, "XiaomiBTLESens_ExecGatttool_Aborted", $hash) unless(exists($hash->{helper}{RUNNING_PID}));
    
    Log3 $name, 4, "XiaomiBTLESens ($name) - WriteDeviceName: call function ExecGatttool_Run";
}

sub XiaomiBTLESens_Set($$@) {
    
    my ($hash, $name, @aa)  = @_;
    my ($cmd, @args)         = @aa;
    

    if( $cmd eq 'devicename' ) {
        return "usage: devicename <name>" if( @args < 1 );

        my $devicename = join( " ", @args );
        XiaomiBTLESens_WriteDeviceName($hash,XiaomiBTLESens_CreateDevicenameHEX($devicename));
    
    } else {
        my $list = "devicename" if( AttrVal($name,'model','thermoHygroSens') eq 'thermoHygroSens' );
        
        return "Unknown argument $cmd, choose one of $list";
    }
    
    return undef;
}

sub XiaomiBTLESens_Get($$@) {
    
    my ($hash, $name, @aa)  = @_;
    my ($cmd, @args)         = @aa;
    

    if( $cmd eq 'sensorData' ) {
        return "usage: sensorData" if( @args != 0 );
    
        XiaomiBTLESens_stateRequest($hash);
        
    } else {
        my $list = "sensorData:noArg";
        return "Unknown argument $cmd, choose one of $list";
    }
    
    return undef;
}

sub XiaomiBTLESens_ExecGatttool_Run($) {

    my $string      = shift;
    
    my ($name,$mac,$gattCmd,$handle,$value) = split("\\|", $string);
    my $sshHost                             = AttrVal($name,"sshHost","none");
    my $gatttool;


    $gatttool                               = qx(which gatttool) if($sshHost eq 'none');
    $gatttool                               = qx(ssh $sshHost 'which gatttool') if($sshHost ne 'none');
    chomp $gatttool;
    
    if(-x $gatttool) {
    
        my $cmd;
        my $loop;
        my @gtResult;
        my $wait    = 1;
        my $sshHost = AttrVal($name,"sshHost","none");
        my $hci     = AttrVal($name,"hciDevice","hci0");
        
        while($wait) {
        
            my $grepGatttool;
            $grepGatttool = qx(ps ax| grep -E \'gatttool -i $hci -b $mac\' | grep -v grep) if($sshHost eq 'none');
            $grepGatttool = qx(ssh $sshHost 'ps ax| grep -E "gatttool -i $hci -b $mac" | grep -v grep') if($sshHost ne 'none');

            if(not $grepGatttool =~ /^\s*$/) {
                Log3 $name, 5, "XiaomiBTLESens ($name) - ExecGatttool_Run: another gatttool process is running. waiting...";
                sleep(1);
            } else {
                $wait = 0;
            }
        }
        
        $cmd .= "ssh $sshHost '" if($sshHost ne 'none');
        $cmd .= "gatttool -i $hci -b $mac ";
        $cmd .= "--char-read -a $handle" if($gattCmd eq 'read');
        $cmd .= "--char-write-req -a $handle -n $value" if($gattCmd eq 'write');
        $cmd = "timeout 15 ".$cmd." --listen" if( AttrVal($name,"model","none") eq 'thermoHygroSens' and $gattCmd eq 'write' and $handle eq '0x10');
        $cmd .= " 2>&1 /dev/null";
        $cmd .= "'" if($sshHost ne 'none');
        $cmd = "ssh $sshHost 'gatttool -i $hci -b $mac --char-write-req -a 0x33 -n A01F && gatttool -i $hci -b $mac --char-read -a 0x35 2>&1 /dev/null'" if($sshHost ne 'none' and $gattCmd eq 'write' and AttrVal($name,"model","none") eq 'flowerSens');
        
        $loop = 0;
        do {
            
            Log3 $name, 5, "XiaomiBTLESens ($name) - ExecGatttool_Run: call gatttool with command $cmd and loop $loop";
            @gtResult = split(": ",qx($cmd));
            Log3 $name, 5, "XiaomiBTLESens ($name) - ExecGatttool_Run: gatttool loop result ".join(",", @gtResult);
            $loop++;
            
            $gtResult[0] = 'connect error'
            unless( defined($gtResult[0]) );
            
        } while( $loop < 5 and $gtResult[0] eq 'connect error' );
        
        Log3 $name, 4, "XiaomiBTLESens ($name) - ExecGatttool_Run: gatttool result ".join(",", @gtResult);
        
        $handle = '0x35' if($sshHost ne 'none' and $gattCmd eq 'write' and AttrVal($name,'model','none') eq 'flowerSens');
        $gattCmd = 'read' if($sshHost ne 'none' and $gattCmd eq 'write' and AttrVal($name,'model','none') eq 'flowerSens');

        $gtResult[1] = 'no data response'
        unless( defined($gtResult[1]) );
        
        my $json_notification = XiaomiBTLESens_encodeJSON($gtResult[1]);
        
        if($gtResult[1] =~ /^([0-9a-f]{2}(\s?))*$/) {
            return "$name|$mac|ok|$gattCmd|$handle|$json_notification";
        } elsif($gtResult[0] ne 'connect error' and $gattCmd eq 'write') {
            if( $sshHost ne 'none' ) {
                XiaomiBTLESens_ExecGatttool_Run($name."|".$mac."|read|0x35");
            } else {
                return "$name|$mac|ok|$gattCmd|$handle|$json_notification";
            }
        } else {
            return "$name|$mac|error|$gattCmd|$handle|$json_notification";
        }
    } else {
        return "$name|$mac|error|$gattCmd|$handle|no gatttool binary found. Please check if bluez-package is properly installed";
    }
}

sub XiaomiBTLESens_ExecGatttool_Done($) {

    my $string      = shift;
    my ($name,$mac,$respstate,$gattCmd,$handle,$json_notification) = split("\\|", $string);
    
    my $hash                = $defs{$name};
    
    
    delete($hash->{helper}{RUNNING_PID});
    
    Log3 $name, 5, "XiaomiBTLESens ($name) - ExecGatttool_Done: Helper is disabled. Stop processing" if($hash->{helper}{DISABLED});
    return if($hash->{helper}{DISABLED});
    
    Log3 $name, 4, "XiaomiBTLESens ($name) - ExecGatttool_Done: gatttool return string: $string";
    
    my $decode_json =   eval{decode_json($json_notification)};
    if($@){
        Log3 $name, 5, "XiaomiBTLESens ($name) - ExecGatttool_Done: JSON error while request: $@";
    }
    
    
    if( $respstate eq 'ok' and $gattCmd eq 'write' and AttrVal($name,'model','none') eq 'flowerSens' ) {
        XiaomiBTLESens_ReadSensData($hash);
        
    } elsif( $respstate eq 'ok' ) {
        XiaomiBTLESens_ProcessingNotification($hash,$handle,$decode_json->{gtResult});
        
    } else {
        XiaomiBTLESens_ProcessingErrors($hash,$decode_json->{gtResult});
    }
}

sub XiaomiBTLESens_ExecGatttool_Aborted($) {

    my ($hash)  = @_;
    my $name    = $hash->{NAME};
    my %readings;

    delete($hash->{helper}{RUNNING_PID});
    readingsSingleUpdate($hash,"state","unreachable", 1);
    
    $readings{'lastGattError'} = 'The BlockingCall Process terminated unexpectedly. Timedout';
    XiaomiBTLESens_WriteReadings($hash,\%readings);

    Log3 $name, 4, "XiaomiBTLESens ($name) - ExecGatttool_Aborted: The BlockingCall Process terminated unexpectedly. Timedout";
}

sub XiaomiBTLESens_ProcessingNotification($@) {

    my ($hash,$handle,$notification)    = @_;
    
    my $name    = $hash->{NAME};
    my $readings;
    
    Log3 $name, 5, "XiaomiBTLESens ($name) - ProcessingNotification";
    
    if( AttrVal($name,'model','none') eq 'flowerSens' ) {
        if( $handle eq '0x38' ) {
            ### Flower Sens - Read Firmware and Battery Data
            Log3 $name, 4, "XiaomiBTLESens ($name) - ProcessingNotification: handle 0x38";
            
            $readings = XiaomiBTLESens_FlowerSensHandle0x38($hash,$notification);
            
        } elsif( $handle eq '0x35' ) {
            ### Flower Sens - Read Sensor Data
            Log3 $name, 4, "XiaomiBTLESens ($name) - ProcessingNotification: handle 0x35";
            
            $readings = XiaomiBTLESens_FlowerSensHandle0x35($hash,$notification);
        }
        
    } elsif( AttrVal($name,'model','none') eq 'thermoHygroSens') {
        if( $handle eq '0x18' ) {
            ### Thermo/Hygro Sens - Read Battery Data
            Log3 $name, 4, "XiaomiBTLESens ($name) - ProcessingNotification: handle 0x18";
            
            $readings = XiaomiBTLESens_ThermoHygroSensHandle0x18($hash,$notification);
        }
        
        elsif( $handle eq '0x10' ) {
            ### Thermo/Hygro Sens - Read Sensor Data
            Log3 $name, 4, "XiaomiBTLESens ($name) - ProcessingNotification: handle 0x10";
            
            $readings = XiaomiBTLESens_ThermoHygroSensHandle0x10($hash,$notification);
        }
        
        elsif( $handle eq '0x24' ) {
            ### Thermo/Hygro Sens - Read Firmware Data
            Log3 $name, 4, "XiaomiBTLESens ($name) - ProcessingNotification: handle 0x24";
        
            $readings = XiaomiBTLESens_ThermoHygroSensHandle0x24($hash,$notification)
        }
        
        elsif( $handle eq '0x3' ) {
            ### Thermo/Hygro Sens - Read and Write Devicename
            Log3 $name, 4, "XiaomiBTLESens ($name) - ProcessingNotification: handle 0x3";
        
            $readings = XiaomiBTLESens_ThermoHygroSensHandle0x3($hash,$notification)
        }
    }
    
    
    XiaomiBTLESens_WriteReadings($hash,$readings);
}

sub XiaomiBTLESens_FlowerSensHandle0x38($$) {
    ### FlowerSens - Read Firmware and Battery Data
    my ($hash,$notification)    = @_;
    
    my $name                    = $hash->{NAME};
    my %readings;
    
    
    Log3 $name, 5, "XiaomiBTLESens ($name) - FlowerSens Handle0x38";

    my @dataBatFw   = split(" ",$notification);
    my $blevel      = hex("0x".$dataBatFw[0]);
    my $fw          = ($dataBatFw[2]-30).".".($dataBatFw[4]-30).".".($dataBatFw[6]-30);
        
    $readings{'batteryLevel'}   = $blevel;
    $readings{'battery'}        = ($blevel > 20?"ok":"low");
    $readings{'firmware'}       = $fw;
        
    $hash->{helper}{CallBattery} = 1;
    XiaomiBTLESens_CallBattery_Timestamp($hash);
    return \%readings;
}

sub XiaomiBTLESens_FlowerSensHandle0x35($$) {
    ### Flower Sens - Read Sensor Data
    my ($hash,$notification)    = @_;
    
    my $name                    = $hash->{NAME};
    my %readings;
    
    
    Log3 $name, 5, "XiaomiBTLESens ($name) - FlowerSens Handle0x35";
    
    my @dataSensor  = split(" ",$notification);


    return XiaomiBTLESens_stateRequest($hash)
    unless( $dataSensor[0] ne "aa" and $dataSensor[1] ne "bb" and $dataSensor[2] ne "cc" and $dataSensor[3] ne "dd" and $dataSensor[4] ne "ee" and $dataSensor[5] ne "ff");


    my $temp;
        
    if( $dataSensor[1] eq "ff" ) {
        $temp       = hex("0x".$dataSensor[1].$dataSensor[0]) - hex("0xffff");
    } else {
        $temp       = hex("0x".$dataSensor[1].$dataSensor[0]);
    }
        
    my $lux         = hex("0x".$dataSensor[4].$dataSensor[3]);
    my $moisture    = hex("0x".$dataSensor[7]);
    my $fertility   = hex("0x".$dataSensor[9].$dataSensor[8]);

    $readings{'temperature'}    = $temp/10;
    $readings{'lux'}            = $lux;
    $readings{'moisture'}       = $moisture;
    $readings{'fertility'}      = $fertility;
        
    $hash->{helper}{CallBattery} = 0;
    return \%readings;
}

sub XiaomiBTLESens_ThermoHygroSensHandle0x18($$) {
    ### Thermo/Hygro Sens - Battery Data
    my ($hash,$notification)    = @_;
    
    my $name                    = $hash->{NAME};
    my %readings;
    
    
    Log3 $name, 5, "XiaomiBTLESens ($name) - Thermo/Hygro Sens Handle0x18";

    my $blevel      = hex("0x".$notification);
        
    $readings{'batteryLevel'}   = $blevel;
    $readings{'battery'}        = ($blevel > 20?"ok":"low");
        
    $hash->{helper}{CallBattery} = 1;
    XiaomiBTLESens_CallBattery_Timestamp($hash);
    return \%readings;
}

sub XiaomiBTLESens_ThermoHygroSensHandle0x10($$) {
    ### Thermo/Hygro Sens - Read Sensor Data
    my ($hash,$notification)    = @_;
    
    my $name                    = $hash->{NAME};
    my %readings;
    
    
    Log3 $name, 5, "XiaomiBTLESens ($name) - Thermo/Hygro Sens Handle0x10";

    $notification =~ s/\s+//g;
                                                                            # 54 3d 31 37 2e 33 20 48 3d 35 32 2e 35 00
    my $temp        = pack('H*',substr($notification,4,8));                 # 31 37 2e 33
    my $hum         = pack('H*',substr($notification,18,8));                # 35 32 2e 35

    $readings{'temperature'}    = $temp;
    $readings{'humidity'}       = $hum;
        
    $hash->{helper}{CallBattery} = 0;
    return \%readings;
}

sub XiaomiBTLESens_ThermoHygroSensHandle0x24($$) {
    ### Thermo/Hygro Sens - Read Firmware Data
    my ($hash,$notification)    = @_;
    
    my $name                    = $hash->{NAME};
    my %readings;
    
    
    Log3 $name, 5, "XiaomiBTLESens ($name) - Thermo/Hygro Sens Handle0x24";

    $notification =~ s/\s+//g;

    my $fw                      = pack('H*',$notification);

    $readings{'firmware'}       = $fw;

    $hash->{helper}{CallBattery} = 0;
    return \%readings;
}

sub XiaomiBTLESens_ThermoHygroSensHandle0x3($$) {
    ### Thermo/Hygro Sens - Read and Write Devicename
    my ($hash,$notification)    = @_;
    
    my $name                    = $hash->{NAME};
    my %readings;
    
    
    Log3 $name, 5, "XiaomiBTLESens ($name) - Thermo/Hygro Sens Handle0x24";

    $notification =~ s/\s+//g;

    my $devname                     = pack('H*',$notification);

    $readings{'devicename'}         = $devname;

    $hash->{helper}{CallBattery}    = 0;
    return \%readings;
}

sub XiaomiBTLESens_WriteReadings($$) {

    my ($hash,$readings)    = @_;
    
    my $name                = $hash->{NAME};


    readingsBeginUpdate($hash);
    while( my ($r,$v) = each %{$readings} ) {
        readingsBulkUpdate($hash,$r,$v);
    }

    readingsBulkUpdateIfChanged($hash, "state", ($readings->{'lastGattError'}?'error':'active'));
    readingsEndUpdate($hash,1);



    
    if( AttrVal($name,'model','none') eq 'flowerSens') {
        if( defined($readings->{temperature}) ) {
            DoTrigger($name, 'minFertility ' . ($readings->{fertility}<AttrVal($name,'minFertility',0)?'low':'ok')) if( AttrVal($name,'minFertility','none') ne 'none' );
            DoTrigger($name, 'maxFertility ' . ($readings->{fertility}>AttrVal($name,'maxFertility',0)?'high':'ok')) if( AttrVal($name,'maxFertility','none') ne 'none' );
        
            DoTrigger($name, 'minMoisture ' . ($readings->{moisture}<AttrVal($name,'minMoisture',0)?'low':'ok')) if( AttrVal($name,'minMoisture','none') ne 'none' );
            DoTrigger($name, 'maxMoisture ' . ($readings->{moisture}>AttrVal($name,'maxMoisture',0)?'high':'ok')) if( AttrVal($name,'maxMoisture','none') ne 'none' );
        
            DoTrigger($name, 'minLux ' . ($readings->{lux}<AttrVal($name,'minLux',0)?'low':'ok')) if( AttrVal($name,'minLux','none') ne 'none' );
            DoTrigger($name, 'maxLux ' . ($readings->{lux}>AttrVal($name,'maxLux',0)?'high':'ok')) if( AttrVal($name,'maxLux','none') ne 'none' );
        }
    }
    
    if( defined($readings->{temperature}) ) {
        DoTrigger($name, 'minTemp ' . ($readings->{temperature}<AttrVal($name,'minTemp',0)?'low':'ok')) if( AttrVal($name,'minTemp','none') ne 'none' );
        DoTrigger($name, 'maxTemp ' . ($readings->{temperature}>AttrVal($name,'maxTemp',0)?'high':'ok')) if( AttrVal($name,'maxTemp','none') ne 'none' );
    }



    
    Log3 $name, 4, "XiaomiBTLESens ($name) - WriteReadings: Readings were written";

    $hash->{helper}{CallSensDataCounter} = 0;
    XiaomiBTLESens_stateRequest($hash) if( $hash->{helper}{CallBattery} == 1 );
}

sub XiaomiBTLESens_ProcessingErrors($$) {

    my ($hash,$notification)    = @_;
    
    my $name                    = $hash->{NAME};
    my %readings;
    
    Log3 $name, 5, "XiaomiBTLESens ($name) - ProcessingErrors";
    $readings{'lastGattError'} = $notification;
    
    XiaomiBTLESens_WriteReadings($hash,\%readings);
}

#### my little Helper
sub XiaomiBTLESens_encodeJSON($) {

    my $gtResult    = shift;
    
    
    chomp($gtResult);
    
    my %response = (
        'gtResult'      => $gtResult
    );
    
    return encode_json \%response;
}

## Routinen damit Firmware und Batterie nur alle X male statt immer aufgerufen wird
sub XiaomiBTLESens_CallBattery_Timestamp($) {

    my $hash    = shift;
    
    
    # get timestamp
    $hash->{helper}{updateTimeCallBattery}      = gettimeofday(); # in seconds since the epoch
    $hash->{helper}{updateTimestampCallBattery} = FmtDateTime(gettimeofday());
}

sub XiaomiBTLESens_CallBattery_UpdateTimeAge($) {

    my $hash    = shift;

    
    $hash->{helper}{updateTimeCallBattery}  = 0 if( not defined($hash->{helper}{updateTimeCallBattery}) );
    my $UpdateTimeAge = gettimeofday() - $hash->{helper}{updateTimeCallBattery};
    
    return $UpdateTimeAge;
}

sub XiaomiBTLESens_CallBattery_IsUpdateTimeAgeToOld($$) {

    my ($hash,$maxAge)    = @_;;
    
    
    return (XiaomiBTLESens_CallBattery_UpdateTimeAge($hash)>$maxAge ? 1:0);
}

sub XiaomiBTLESens_CreateDevicenameHEX($) {

    my $devicename      = shift;
    
    my $devicenameHex = unpack("H*", $devicename);
    

    return $devicenameHex;
}




1;








=pod
=item device
=item summary       Modul to retrieves data from a Xiaomi BTLE Sensor
=item summary_DE    Modul um Daten vom Xiaomi BTLE Sensor aus zu lesen

=begin html

<a name="XiaomiBTLESens"></a>
<h3>Xiaomi BTLE Sensor</h3>
<ul>
  <u><b>XiaomiBTLESens - Retrieves data from a Xiaomi BTLE Sensor</b></u>
  <br>
  With this module it is possible to read the data from a sensor and to set it as reading.</br>
  Gatttool and hcitool is required to use this modul. (apt-get install bluez)
  <br><br>
  <a name="XiaomiBTLESensdefine"></a>
  <b>Define</b>
  <ul><br>
    <code>define &lt;name&gt; XiaomiBTLESens &lt;BT-MAC&gt;</code>
    <br><br>
    Example:
    <ul><br>
      <code>define Weihnachtskaktus XiaomiBTLESens C4:7C:8D:62:42:6F</code><br>
    </ul>
    <br>
    This statement creates a XiaomiBTLESens with the name Weihnachtskaktus and the Bluetooth Mac C4:7C:8D:62:42:6F.<br>
    After the device has been created, the current data of the Xiaomi BTLE Sensor is automatically read from the device.
  </ul>
  <br><br>
  <a name="XiaomiBTLESensreadings"></a>
  <b>Readings</b>
  <ul>
    <li>state - Status of the flower sensor or error message if any errors.</li>
    <li>battery - current battery state dependent on batteryLevel.</li>
    <li>batteryLevel - current battery level in percent.</li>
    <li>fertility - Values for the fertilizer content</li>
    <li>firmware - current device firmware</li>
    <li>lux - current light intensity</li>
    <li>moisture - current moisture content</li>
    <li>temperature - current temperature</li>
  </ul>
  <br><br>
  <a name="XiaomiBTLESensset"></a>
  <b>Set</b>
  <ul>
    <li></li>
    <br>
  </ul>
  <br><br>
  <a name="XiaomiBTLESensget"></a>
  <b>Get</b>
  <ul>
    <li>sensorData - retrieves the current data of the Xiaomi sensor</li>
    <br>
  </ul>
  <br><br>
  <a name="XiaomiBTLESensattribut"></a>
  <b>Attributes</b>
  <ul>
    <li>disable - disables the device</li>
    <li>disabledForIntervals - disable device for interval time (13:00-18:30 or 13:00-18:30 22:00-23:00)</li>
    <li>interval - interval in seconds for statusRequest</li>
    <li>minFertility - min fertility value for low warn event</li>
    <li>maxFertility - max fertility value for High warn event</li>
    <li>minMoisture - min moisture value for low warn event</li>
    <li>maxMoisture - max moisture value for High warn event</li>
    <li>minTemp - min temperature value for low warn event</li>
    <li>maxTemp - max temperature value for high warn event</li>
    <li>minlux - min lux value for low warn event</li>
    <li>maxlux - max lux value for high warn event
    <br>
    Event Example for min/max Value's: 2017-03-16 11:08:05 XiaomiBTLESens Dracaena minMoisture low<br>
    Event Example for min/max Value's: 2017-03-16 11:08:06 XiaomiBTLESens Dracaena maxTemp high</li>
    <li>sshHost - FQD-Name or IP of ssh remote system / you must configure your ssh system for certificate authentication. For better handling you can config ssh Client with .ssh/config file</li>
    <li>batteryFirmwareAge - how old can the reading befor fetch new data</li>
    <li>blockingCallLoglevel - Blocking.pm Loglevel for BlockingCall Logoutput</li>
  </ul>
</ul>

=end html

=begin html_DE

<a name="XiaomiBTLESens"></a>
<h3>Xiaomi BTLE Sensor</h3>
<ul>
  <u><b>XiaomiBTLESens - liest Daten von einem Xiaomi BTLE Sensor</b></u>
  <br />
  Dieser Modul liest Daten von einem Sensor und legt sie in den Readings ab.<br />
  Auf dem (Linux) FHEM-Server werden gatttool und hcitool vorausgesetzt. (sudo apt install bluez)
  <br /><br />
  <a name="XiaomiBTLESensdefine"></a>
  <b>Define</b>
  <ul><br />
    <code>define &lt;name&gt; XiaomiBTLESens &lt;BT-MAC&gt;</code>
    <br /><br />
    Beispiel:
    <ul><br />
      <code>define Weihnachtskaktus XiaomiBTLESens C4:7C:8D:62:42:6F</code><br />
    </ul>
    <br />
    Der Befehl legt ein Device vom Typ XiaomiBTLESens an mit dem Namen Weihnachtskaktus und der Bluetooth MAC C4:7C:8D:62:42:6F.<br />
    Nach dem Anlegen des Device werden umgehend und automatisch die aktuellen Daten vom betroffenen Xiaomi BTLE Sensor gelesen.
  </ul>
  <br /><br />
  <a name="XiaomiBTLESensreadings"></a>
  <b>Readings</b>
  <ul>
    <li>state - Status des BTLE Sensor oder eine Fehlermeldung falls Fehler beim letzten Kontakt auftraten.</li>
    <li>battery - aktueller Batterie-Status in Abhängigkeit vom Wert batteryLevel.</li>
    <li>batteryLevel - aktueller Ladestand der Batterie in Prozent.</li>
    <li>fertility - Wert des Fruchtbarkeitssensors (Bodenleitf&auml;higkeit)</li>
    <li>firmware - aktuelle Firmware-Version des BTLE Sensor</li>
    <li>lux - aktuelle Lichtintensit&auml;t</li>
    <li>moisture - aktueller Feuchtigkeitswert</li>
    <li>temperature - aktuelle Temperatur</li>
  </ul>
  <br /><br />
  <a name="XiaomiBTLESensset"></a>
  <b>Set</b>
  <ul>
    <li></li>
    <br />
  </ul>
  <br /><br />
  <a name="XiaomiBTLESensGet"></a>
  <b>Get</b>
  <ul>
    <li>sensorData - aktive Abfrage der Sensors Werte</li>
    <br />
  </ul>
  <br /><br />
  <a name="XiaomiBTLESensattribut"></a>
  <b>Attribute</b>
  <ul>
    <li>disable - deaktiviert das Device</li>
    <li>interval - Interval in Sekunden zwischen zwei Abfragen</li>
    <li>disabledForIntervals - deaktiviert das Gerät für den angegebenen Zeitinterval (13:00-18:30 or 13:00-18:30 22:00-23:00)</li>
    <li>minFertility - min Fruchtbarkeits-Grenzwert f&uuml;r ein Ereignis minFertility low </li>
    <li>maxFertility - max Fruchtbarkeits-Grenzwert f&uuml;r ein Ereignis maxFertility high </li>
    <li>minMoisture - min Feuchtigkeits-Grenzwert f&uuml;r ein Ereignis minMoisture low </li> 
    <li>maxMoisture - max Feuchtigkeits-Grenzwert f&uuml;r ein Ereignis maxMoisture high </li>
    <li>minTemp - min Temperatur-Grenzwert f&uuml;r ein Ereignis minTemp low </li>
    <li>maxTemp - max Temperatur-Grenzwert f&uuml;r ein Ereignis maxTemp high </li>
    <li>minlux - min Helligkeits-Grenzwert f&uuml;r ein Ereignis minlux low </li>
    <li>maxlux - max Helligkeits-Grenzwert f&uuml;r ein Ereignis maxlux high
    <br /><br />Beispiele f&uuml;r min/max-Ereignisse:<br />
    2017-03-16 11:08:05 XiaomiBTLESens Dracaena minMoisture low<br />
    2017-03-16 11:08:06 XiaomiBTLESens Dracaena maxTemp high<br /><br /></li>
    <li>sshHost - FQDN oder IP-Adresse eines entfernten SSH-Systems. Das SSH-System ist auf eine Zertifikat basierte Authentifizierung zu konfigurieren. Am elegantesten geschieht das mit einer  .ssh/config Datei auf dem SSH-Client.</li>
    <li>batteryFirmwareAge - wie alt soll der Timestamp des Readings sein bevor eine Aktuallisierung statt findet</li>
    <li>blockingCallLoglevel - Blocking.pm Loglevel für BlockingCall Logausgaben</li>
  </ul>
</ul>

=end html_DE

=cut
