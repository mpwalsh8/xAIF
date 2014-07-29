# vim: set expandtab tabstop=4 shiftwidth=4:
#
#  I like Vim (http://www.vim.org) as a text editor.  The above line
#  tells Vim to set the indent to 4 spaces and the tab key to indent
#  4 spaces.
# 
#  ImportAIF.tcl
#
#  Tcl based Mentor Graphics Automation solution to Import an AIF file and
#  generate Pad, Padstack, Cell, and PDB to be used in a IC Package design.
#  This script should be run with "wish" or "tclsh" - it cannot be dragged
#  onto LM.
#
#  This script requires Tcl 8.4.19.  Tcl 8.5.x and 8.6.x are not supported
#  by the Mentor Graphics COM API interface.  You can download Tcl 8.4.19
#  from ActiveState.com:
#
#    http://www.activestate.com/activetcl/downloads
#
#
#  (c) November 2010 - Mentor Graphics Corporation
#
#  Mike Walsh - mike_walsh@mentor.com
#
#  Mentor Graphics Corporation
#  1001 Winstead Drive, Suite 380
#  Cary, North Carolina 27513
#
#  This software is NOT officially supported by Mentor Graphics.
#
#  ####################################################################
#  ####################################################################
#  ## The following  software  is  "freeware" which  Mentor Graphics ##
#  ## Corporation  provides as a courtesy  to our users.  "freeware" ##
#  ## is provided  "as is" and  Mentor  Graphics makes no warranties ##
#  ## with  respect  to "freeware",  either  expressed  or  implied, ##
#  ## including any implied warranties of merchantability or fitness ##
#  ## for a particular purpose.                                      ##
#  ####################################################################
#  ####################################################################
#
#  Change Log:
#
#    10/29/2010 - Initial version.
#    11/14/2010 - Added error checking and handling for access
#                 to Parts Editor database.
#    11/15/2010 - Added Cell Placement Outline.
#    11/18/2010 - Improved error checking and handling to enable
#                 support for both Central Library and PCB Design
#                 as a target.
#    11/19/2010 - Added intial support for PCB database support.
#    11/22/2010 - Added ability to build pads and padstacks in
#                 design mode.
#    11/23/2010 - Added ability to build cell in design mode.
#    12/01/2010 - Added ability to generate a PDB in design mode.
#                 PDB still suffers from symbol reference bug.
#                 Cleaned up debug code and added some error
#                 checking.
#    12/02/2010 - Cleaned up debug code and fixed some error checking.
#    03/25/2011 - Added transactions to cell generation and run time
#                 reporting.
#    03/30/2011 - Added dialog boxes to prompt for Cell and PDB
#                 partition when running in Central Library mode.
#                 This replaces the creation of a new partitions
#                 based on the name of the source die.
#    08/10/2011 - Added "Sparse" mode to allow generation of a sparse
#                 Cell and PDB.  A sparse Cell and PDB allow Expedition
#                 to run more efficiently with extremely large devices.
#    04/10/2014 - Adapted ImportDie.tcl to support AIF
#    05/16/2014 - Basic AIF import working with support for square and
#                 rectangular pads.
#    05/29/2014 - Added sclable zooming and pin tex handling.  Adapted
#                 from example found at:  http://wiki.tcl.tk/4844
#    06/02/2014 - Fixed scroll bars on all ctext widgets and canvas.
#    06/20/2014 - Added balls and bond fingers from AIF netlist.
#    06/24/2014 - Add support for oblong shaped pads.
#    06/25/2014 - Separated pad and refdes text from the object list
#                 so they couldbe managed individually.  Add support
#                 rotation of rectangular and oblong pads.
#    06/26/2014 - Oblong pads are displayed correctly and support rotation.
#    07/14/2014 - New view of AIF netlist implemented using TableList widget.
#    07/18/2014 - New Viewing models, bond wire connections, and net line
#                 connections all added and working.
#    07/20/2014 - Moved large chunks of code into separate files and 
#                 namespaces to make ease of maintenance/development easier.
#
#
#    Useful links:
#      Drawing rounded polygons:  http://wiki.tcl.tk/8590
#      Drawing rounded rectangles:  http://wiki.tcl.tk/1416
#      Drawing regular polygons:  http://wiki.tcl.tk/8398
#

package require tile
package require tcom
package require ctext
package require csv
package require inifile
package require tablelist
package require Tk 8.4
#package require math::bigfloat

##  Load the Mentor DLLs.
::tcom::import "$env(SDD_HOME)/wg/$env(SDD_PLATFORM)/bin/ExpeditionPCB.exe"
::tcom::import "$env(SDD_HOME)/wg/$env(SDD_PLATFORM)/lib/CellEditorAddin.dll"
::tcom::import "$env(SDD_HOME)/common/$env(SDD_PLATFORM)/lib/PDBEditor.dll"
::tcom::import "$env(SDD_HOME)/common/$env(SDD_PLATFORM)/lib/PadstackEditor.dll"

#
#  Initialize the ediu namespace
#
proc ediuInit {} {

    ##  define variables in the ediu namespace
    array unset ::ediu
    array set ::ediu {
        busy "Busy"
        ready "Ready"
        Nothing ""
        mode ""
        designMode "Design"
        libraryMode "Central Library"
        sparseMode 0
        AIFFile ""
        #sparsePinsFile ""
        targetPath ""
        PCBDesign ""
        CentralLibrary ""
	    filename ""
        #sparsepinsfile ""
        statusLine ""
        notebook ""
        dashboard ""
        transcript ""
        sourceview ""
        layoutview ""
        netlistview ""
        #sparsepinsview ""
        EDIU "Expedition AIF Import Utility"
        MsgNote 0
        MsgWarning 1
        MsgError 2
        pdstkEdtr ""
        pdstkEdtrDb ""
        cellEdtr ""
        cellEdtrDb ""
        cellEdtrPrtn ""
        cellEdtrPrtnName ""
        cellEdtrPrtnNames {}
        partEdtr ""
        partEdtrDb ""
        partEdtrPrtn ""
        partEdtrPrtnName ""
        partEdtrPrtnNames {}
        pcbApp ""
        pcbDoc ""
        appVisible True
        connectMode True
        sTime ""
        cTime ""
        consoleEcho "True"
        #sparsepinnames {}
        #sparsepinnumbers {}
        LeftBracket "\["
        RightBracket "\]"
        BackSlash "\\"
        ScaleFactor 1
        BGA 0
        MCMAIF 0
        DIEREF "U1"
        BGAREF "A1"
    }

    ##  Keywords to scan for in AIF file
    array unset ::sections
    #array set ::sections {
    #    die "die_name"
    #    padGeomName "pad_geom_name"
    #    padGeomShape "pad_geom_shape"
    #    dieActiveSize "die_active_size"
    #    dieSize "die_size"
    #    diePads "die_pads"
    #}

    ##  Sections within the AIF file
    array set ::sections {
        database "DATABASE"
        die "DIE"
        diePads "PADS"
        netlist "NETLIST"
        bga "BGA"
        mcm_die "MCM_DIE"
    }

    array set ::ignored {
        rings "RINGS"
        bondable_ring_area "BONDABLE_RING_AREA"
        wire "WIRE"
        fiducials "FIDUCIALS"
        die_logo "DIE_LOGO"
    }

    ##  Namespace array to store widgets
    array unset ::widgets
    array set ::widgets {
        setupmenu ""
        viewmenu ""
        transcript ""
        sourceview ""
        layoutview ""
        netlistview ""
        kynnetlistview ""
        #sparsepinsview ""
        statuslight ""
        progressbar ".ProgressBar"
        design ""
        library ""
        windowSizeX 800
        windowSizeY 600
        mode ""
        AIFFile ""
        AIFType "File Type:"
        targetPath ""
        CellPartnDlg ".chooseCellPartitionDialog"
        PartPartnDlg ".choosePartPartitionDialog"
    }

    ##  Default to design mode
    set ::ediu(mode) $::ediu(designMode)

    ##  Supported units
    set ::units [list um mm cm inch mil]

    ##  Supported pad shapes
    set ::padshapes [list circle round oblong obround rectangle rect square sq poly]

    ##  Initialize the AIF data structures
    ediuAIFFileInit
}

##
##  ediuAIFFileInit
##
proc ediuAIFFileInit { } {

    ##  Database Details
    array set ::database {
        type ""
        version ""
        units "um"
        mcm "FALSE"
    }

    ##  Die Details
    array set ::die {
        name ""
        refdes "U1"
        width 0
        height 0
        center { 0 0 }
        partition ""
    }

    ##  BGA Details
    array set ::bga {
        name ""
        refdes "A1"
        width 0
        height 0
    }

    ##  Store devices in a Tcl list
    array set ::devices {}

    ##  Store mcm die in a Tcl dictionary
    set ::mcmdie [dict create]

    ##  Store pads in a Tcl dictionary
    set ::pads [dict create]
    set ::padtypes [dict create]

    ##  Store net names in a Tcl list
    set ::netnames [list]

    ##  Store netlist in a Tcl list
    set ::netlist [list]
    set ::netlines [list]

    ##  Store bondpad connections in a Tcl list
    set ::bondpads [list]
    set ::bondwires [list]
}

#
#  Transcript a message with a severity level
#
proc Transcript {severity messagetext} {
    #  Create a message based on severity, default to Note.
    if {$severity == $::ediu(MsgNote)} {
        set msg [format "# Note:  %s" $messagetext]
    } elseif {$severity == $::ediu(MsgWarning)} {
        set msg [format "# Warning:  %s" $messagetext]
    } elseif {$severity == $::ediu(MsgError)} {
        set msg [format "# Error:  %s" $messagetext]
    } else  {
        set msg [format "# Note:  %s" $messagetext]
    }

    set txt $GUI::widgets(transcript)
    $txt configure -state normal
    $txt insert end "$msg\n"
    $txt see end
    $txt configure -state disabled
    set GUI::widgets(lastmsg) $msg
    update idletasks

    if { $::ediu(consoleEcho) } {
        puts $msg
    }
}

#
#  ediuChooseCellPartition
#
proc ediuChooseCellPartition-deprecated {} {
    set dlg $GUI::widgets(CellPartnDlg)

    puts [$dlg.f.cellpartition.list curselection]
    puts [$dlg.f.cellpartition.list get [$dlg.f.cellpartition.list curselection]]

    Transcript $::ediu(MsgNote) [format "Cell Partition \"%s\" selected." $::ediu(cellEdtrPrtnName)]

    #destroy $dlg
}

#
#  ediuChooseCellPartitionDialog
#
#  When running in Central Library mode the cell
#  partition must be specified by the user.  The
#  the list of existing partitions is presented to
#  the user to select from.
#

proc ediuChooseCellPartitionDialog-deprecated {} {
    set dlg $GUI::widgets(CellPartnDlg)

    #  Create the top level window and withdraw it
    toplevel  $dlg
    wm withdraw $dlg

    #  Create the frame
    ttk::frame $dlg.f -relief flat

    #  Central Library Cell Partition
    ttk::labelframe $dlg.f.cellpartition -text "Cell Partitions"
    listbox $dlg.f.cellpartition.list -relief raised -borderwidth 2 \
        -yscrollcommand "$dlg.f.cellpartition.scroll set" \
        -listvariable ::ediu(cellEdtrPrtnNames)
    ttk::scrollbar $dlg.f.cellpartition.scroll -command "$dlg.f.cellpartition.list yview"
    pack $dlg.f.cellpartition.list $dlg.f.cellpartition.scroll \
        -side left -fill both -expand 1 -in $dlg.f.cellpartition
    grid rowconfigure $dlg.f.cellpartition 0 -weight 1
    grid columnconfigure $dlg.f.cellpartition 0 -weight 1

    #pack $dlg.f.cellpartition -fill both
    #ttk::label $dlg.f.cellpartition.namel -text "Partition:"
    #ttk::entry $dlg.f.cellpartition.namet -textvariable ::ediu(cellEdtrPrtnName)

    #  Layout the dialog box
    #pack $dlg.f.cellpartition.list $dlg.f.cellpartition.scroll -side left -fill both
    grid config $dlg.f.cellpartition.list -row 0 -column 0 -sticky wnse
    grid config $dlg.f.cellpartition.scroll -row 0 -column 1 -sticky ns
    #grid config $dlg.f.cellpartition.namel -column 0 -row 1 -sticky e
    #grid config $dlg.f.cellpartition.namet -column 1 -row 1 -sticky snew


    #grid config $dlg.f.cellpartition -sticky ns
    pack $dlg.f.cellpartition -padx 25 -pady 25 -fill both -in $dlg.f -expand 1
    # grid rowconfigure $dlg.f.cellpartition -columnspan 2

    #  Action buttons

    ttk::frame $dlg.f.buttons -relief flat

    ttk::button $dlg.f.buttons.ok -text "Ok" -command { ediuChooseCellPartition }
    ttk::button $dlg.f.buttons.cancel -text "Cancel" -command { destroy $GUI::widgets(CellPartnDlg) }
    
    pack $dlg.f.buttons.ok -side left
    pack $dlg.f.buttons.cancel -side right
    pack $dlg.f.buttons -padx 5 -pady 10 -ipadx 10

    pack $dlg.f.buttons -in $dlg.f -expand 1

    grid rowconfigure $dlg.f 0 -weight 1
    grid rowconfigure $dlg.f 1 -weight 0

    pack $dlg.f -fill x -expand 1

    #  Window manager settings for dialog
    wm title $dlg "Select Cell Partition"
    wm protocol $dlg WM_DELETE_WINDOW {
        $GUI::widgets(CellPartnDlg).f.buttons.cancel invoke
    }
    wm transient $dlg

    #  Ready to display the dialog
    wm deiconify $dlg

    #  Make this a modal dialog
    catch { tk visibility $dlg }
    #focus $dlg.f.cellpartition.namet
    catch { grab set $dlg }
    catch { tkwait window $dlg }
}

#
#  ediuGraphicViewBuild
#
proc ediuGraphicViewBuild {} {
    set rv 0
    set line_no 0
    set vm $GUI::widgets(viewmenu)
    $vm.devices add separator

    set cnvs $GUI::widgets(layoutview)
    set txt $GUI::widgets(netlistview)
    set nlt $GUI::widgets(netlisttable)
    set kyn $GUI::widgets(kynnetlistview)
    #set pb $GUI::widgets(progressbar)
    
    #puts "1A - $pb"
    #toplevel $pb
    #puts "1B"
    #ttk::progressbar $pb.pb -orient horizontal -mode indeterminate
    #puts "1C"
    #grid $pb.pb
    #puts "1D"
    #update idletasks
    #puts "1E"

    $cnvs delete all

    ##  Add the outline
    #ediuGraphicViewAddOutline

    ##  Draw the BGA outline (if it exists)
    if { $::ediu(BGA) == 1 } {
        ediuDrawBGAOutline
        set ::devices($::bga(name)) [list]

        #  Add BGA to the View Devices menu and make it visible
        set GUI::devices($::bga(name)) on
        $vm.devices add checkbutton -label "$::bga(name)" -underline 0 \
            -variable GUI::devices($::bga(name)) -onvalue on -offvalue off \
            -command  "GUI::Visibility $::bga(name) -mode toggle"
            
        $vm.devices add separator
    }

    ##  Is this an MCM-AIF?

    if { $::ediu(MCMAIF) == 1 } {
        foreach i [AIF::MCMDie::GetAllDie] {
            #set section [format "MCM_%s_%s" [string toupper $i] [dict get $::mcmdie $i]]
            set section [format "MCM_%s_%s" [dict get $::mcmdie $i] $i]
            if { [lsearch -exact [AIF::Sections] $section] != -1 } {
                array set part {
                    REF ""
                    NAME ""
                    WIDTH 0.0
                    HEIGHT 0.0
                    CENTER [list 0.0 0.0]
                    X 0.0
                    Y 0.0
                }

                #  Extract each of the expected keywords from the section
                foreach key [array names part] {
                    if { [lsearch -exact [AIF::Variables $section] $key] != -1 } {
                        set part($key) [AIF::GetVar $key $section]
                    }
                }

                #  Need the REF designator for later

                set part(REF) $i
                set ::devices($part(NAME)) [list]

                #  Split the CENTER keyword into X and Y components
                #
                #  The AIF specification and sample file have the X and Y separated by
                #  both a space and comma character so we'll plan to handle either situation.
                if { [llength [split $part(CENTER) ,]] == 2 } {
                    set part(X) [lindex [split $part(CENTER) ,] 0]
                    set part(Y) [lindex [split $part(CENTER) ,] 1]
                } else {
                    set part(X) [lindex [split $part(CENTER)] 0]
                    set part(Y) [lindex [split $part(CENTER)] 1]
                }

                #  Draw the Part Outline
                ediuDrawPartOutline $part(REF) $part(HEIGHT) $part(WIDTH) $part(X) $part(Y)

                #  Add part to the View Devices menu and make it visible
                set GUI::devices($part(REF)) on
                $vm.devices add checkbutton -label "$part(REF)" -underline 0 \
                    -variable GUI::devices($part(REF)) -onvalue on -offvalue off \
                    -command  "GUI::Visibility device-$part(REF) -mode toggle"
            }
        }
    } else {
        if { [lsearch -exact [AIF::Sections] DIE] != -1 } {
            array set part {
                REF ""
                NAME ""
                WIDTH 0.0
                HEIGHT 0.0
                CENTER { 0.0 0.0 }
                X 0.0
                Y 0.0
            }

            #  Extract each of the expected keywords from the section
            foreach key [array names part] {
                if { [lsearch -exact [AIF::Variables DIE] $key] != -1 } {
                    set part($key) [AIF::GetVar $key DIE]
                }
            }

            #  Need the REF designator for later

            set part(REF) $::ediu(DIEREF)
            set ::devices($part(NAME)) [list]

            #  Split the CENTER keyword into X and Y components
            #
            #  The AIF specification and sample file have the X and Y separated by
            #  both a space and comma character so we'll plan to handle either situation.
            if { [llength [split $part(CENTER) ,]] == 2 } {
                set part(X) [lindex [split $part(CENTER) ,] 0]
                set part(Y) [lindex [split $part(CENTER) ,] 1]
            } else {
                set part(X) [lindex [split $part(CENTER)] 0]
                set part(Y) [lindex [split $part(CENTER)] 1]
            }

            #  Draw the Part Outline
            ediuDrawPartOutline $part(REF) $part(HEIGHT) $part(WIDTH) $part(X) $part(Y)

            #  Add part to the View Devices menu and make it visible
            set GUI::devices($part(REF)) on
            $vm.devices add checkbutton -label "$part(REF)" -underline 0 \
                -variable GUI::devices($part(REF)) -onvalue on -offvalue off \
                -command  "GUI::Visibility device-$part(REF) -mode toggle"
        }
    }

    ##  Load the NETLIST section

    set nl [$txt get 1.0 end]

    ##  Clean up netlist table
    #$nlt configure -state normal
    $nlt delete 0 end

    ##  Process the netlist looking for the pads

    foreach n [split $nl '\n'] {
        #puts "==>  $n"
        incr line_no
        ##  Skip blank or empty lines
        if { [string length $n] == 0 } { continue }

        set net [regexp -inline -all -- {\S+} $n]
        set netname [lindex [regexp -inline -all -- {\S+} $n] 0]

        ##  Put netlist into table for easy review

        $nlt insert end $net

        ##  Initialize array to store netlist fields

        array set nlr {
            NETNAME "-"
            PADNUM "-"
            PADNAME "-"
            PAD_X "-"
            PAD_Y "-"
            BALLNUM "-"
            BALLNAME "-"
            BALL_X "-"
            BALL_Y "-"
            FINNUM "-"
            FINNAME "-"
            FIN_X "-"
            FIN_Y "-"
            ANGLE "-"
        }

        #  A simple netlist has 5 fields

        set nlr(NETNAME) [lindex $net 0]
        set nlr(PADNUM) [lindex $net 1]
        set nlr(PADNAME) [lindex $net 2]
        set nlr(PAD_X) [lindex $net 3]
        set nlr(PAD_Y) [lindex $net 4]

        #  A simple netlist with ball assignment has 6 fields
        if { [llength [split $net]] > 5 } {
            set nlr(BALLNUM) [lindex $net 5]
        }

        #  A complex netlist with ball and rings assignments has 14 fields
        if { [llength [split $net]] > 6 } {
            set nlr(BALLNAME) [lindex $net 6]
            set nlr(BALL_X) [lindex $net 7]
            set nlr(BALL_Y) [lindex $net 8]
            set nlr(FINNUM [lindex $net 9]
            set nlr(FINNAME) [lindex $net 10]
            set nlr(FIN_X) [lindex $net 11]
            set nlr(FIN_Y) [lindex $net 12]
            set nlr(ANGLE) [lindex $net 13]
        }

        #printArray nlr

        #  Check the netname and store it for later use
        if { [ regexp {^[[:alpha:][:alnum:]_]*\w} $netname ] == 0 } {
            Transcript $::ediu(MsgError) [format "Net name \"%s\" is not supported AIF syntax." $netname]
            set rv -1
        } else {
            if { [lsearch -exact $::netlist $netname ] == -1 } {
                #lappend ::netlist $netname
                Transcript $::ediu(MsgNote) [format "Found net name \"%s\"." $netname]
            }
        }

        ##  Can the die pad be placed?

        if { $nlr(PADNAME) != "-" } {
            set ref [lindex [split $nlr(PADNUM) "."] 0]
            if { $ref == $nlr(PADNUM) } {
                set padnum $nlr(PADNUM)
                set ref $::ediu(DIEREF)
            } else {
                set padnum [lindex [split $nlr(PADNUM) "."] 1]
            }

            #puts "---------------------> Die Pad:  $ref-$padnum"

            ##  Record the pad and location in the device list
            if { $::ediu(MCMAIF) == 1 } {
                set name [dict get $::mcmdie $ref]
            } else {
                set name [AIF::GetVar NAME DIE]
            }

            lappend ::devices($name) [list $nlr(PADNAME) $padnum $nlr(PAD_X) $nlr(PAD_Y)]

            ediuGraphicViewAddPin $nlr(PAD_X) $nlr(PAD_Y) $nlr(PADNUM) $nlr(NETNAME) $nlr(PADNAME) $line_no "diepad pad pad-$nlr(PADNAME) $ref"
            if { ![dict exists $::padtypes $nlr(PADNAME)] } {
                dict lappend ::padtypes $nlr(PADNAME) "diepad"
            }
        } else {
            Transcript $::ediu(MsgWarning) [format "Skipping die pad for net \"%s\" on line %d, no pad assignment." $netname, $line_no]
        }

        ##  Can the BALL pad be placed?

        if { $nlr(BALLNAME) != "-" } {
            #puts "---------------------> Ball"

            ##  Record the pad and location in the device list
            lappend ::devices($::bga(name)) [list $nlr(BALLNAME) $nlr(BALLNUM) $nlr(BALL_X) $nlr(BALL_Y)]
            #puts "---------------------> Ball Middle"

            ediuGraphicViewAddPin $nlr(BALL_X) $nlr(BALL_Y) $nlr(BALLNUM) $nlr(NETNAME) $nlr(BALLNAME) $line_no "ballpad pad pad-$nlr(BALLNAME)" "white" "red"
            #puts "---------------------> Ball Middle"
            if { ![dict exists $::padtypes $nlr(BALLNAME)] } {
                dict lappend ::padtypes $nlr(BALLNAME) "ballpad"
            }
            #puts "---------------------> Ball End"
        } else {
            Transcript $::ediu(MsgWarning) [format "Skipping ball pad for net \"%s\" on line %d, no ball assignment." $netname, $line_no]
        }

        ##  Can the Finger pad be placed?

        if { $nlr(FINNAME) != "-" } {
            #puts "---------------------> Finger"
            ediuGraphicViewAddPin $nlr(FIN_X) $nlr(FIN_Y) $nlr(FINNUM) $nlr(NETNAME) $nlr(FINNAME) $line_no "bondpad pad pad-$nlr(FINNAME)" "purple" "white" $nlr(ANGLE)
            lappend ::bondpads [list $nlr(NETNAME) $nlr(FINNAME) $nlr(FIN_X) $nlr(FIN_Y) $nlr(ANGLE)]
            if { ![dict exists $::padtypes $nlr(FINNAME)] } {
                dict lappend ::padtypes $nlr(FINNAME) "bondpad"
            }
        } else {
            Transcript $::ediu(MsgWarning) [format "Skipping finger for net \"%s\" on line %d, no finger assignment." $netname, $line_no]
        }

        ##  Need to detect connections - there are two types:
        ##
        ##  1)  Bond Pad connections
        ##  2)  Any other connection (Die to Die,  Die to BGA, etc.)
        ##

        ##  Look for bond wire connections

        if { $nlr(PAD_X) != "-"  && $nlr(PAD_Y) != "-"  && $nlr(FIN_X) != "-"  && $nlr(FIN_Y) != "-" } {
            lappend ::bondwires [list $nlr(NETNAME) $nlr(PAD_X) $nlr(PAD_Y) $nlr(FIN_X) $nlr(FIN_Y)]
        }

        ##  Look for net line connections (which are different than netlist connections)

        if { $nlr(PAD_X) != "-"  && $nlr(PAD_Y) != "-"  && $nlr(BALL_X) != "-"  && $nlr(BALL_Y) != "-" } {
            lappend ::netlines [list $nlr(NETNAME) $nlr(PAD_X) $nlr(PAD_Y) $nlr(BALL_X) $nlr(BALL_Y)]
        }

        ##  Add any connections to the netlist

        if { $nlr(BALL_X) != "-"  && $nlr(BALL_Y) != "-" } {
            if { $nlr(PAD_X) != "-"  && $nlr(PAD_Y) != "-" } {
                lappend ::netlist [list $nlr(NETNAME) $nlr(PADNUM) [format "%s.%s" $::bga(refdes) $nlr(BALLNUM)]]
            } else {
                lappend ::netlist [list $nlr(NETNAME) [format "%s.%s" $::bga(refdes) $nlr(BALLNUM)]]
            }
        }
    }

    ##  Due to the structure of the AIF file, it is possible to have
    ##  replicated pins in our device list.  Need to roll through them
    ##  and make sure all of the stored lists are unique.

    foreach d [array names ::devices] {
        set ::devices($d) [lsort -unique $::devices($d)]
    }

    #  Generate KYN Netlist
    $kyn configure -state normal

    ##  Netlist file header 
    $kyn insert end ";; V4.1.0\n"
    $kyn insert end "%net\n"
    $kyn insert end "%Prior=1\n\n"
    $kyn insert end "%page=0\n"

    ##  Netlist content
    set p ""
    foreach n $::netlist {
        set c ""
        foreach i $n {
            if { [lsearch $n $i] == 0 } {
                set c $i
                if { $c == $p } {
                    $kyn insert end "*  "
                } else {
                    $kyn insert end "\\$i\\  "
                }
            } else {
                set p [split $i "."]
                if { [llength $p] > 1 } {
                    $kyn insert end [format " \\%s\\-\\%s\\" [lindex $p 0] [lindex $p 1]]
                } else {
                    $kyn insert end [format " \\%s\\-\\%s\\" $::ediu(DIEREF) [lindex $p 0]]
                }
            }
        }

        set p $c
        $kyn insert end "\n"
        #puts "$n"
    }

    ##  Output the part list
    $kyn insert end "\n%Part\n"
    foreach i [AIF::MCMDie::GetAllDie] {
        $kyn insert end [format "\\%s\\   \\%s\\\n" [dict get $::mcmdie $i] $i]
    }
    
    ##  If there is a BGA, make sure to put it in the part list
    if { $::ediu(BGA) == 1 } {
        $kyn insert end [format "\\%s\\   \\%s\\\n" $::bga(name) $::bga(refdes)]
    }

    $kyn configure -state disabled

    #  Draw Bond Wires
    foreach bw $::bondwires {
        foreach {net x1 y1 x2 y2} $bw {
            #puts [format "Wire (%s) -- X1:  %s  Y1:  %s  X2:  %s  Y2:  %s" $net $x1 $y1 $x2 $y2]
            $cnvs create line $x1 $y1 $x2 $y2 -tags "bondwire bondwire-$net" -fill "orange" -width 1

            #  Add bond wire to the View Bond Wires menu and make it visible
            #  Because a net can have more than one bond wire, need to ensure
            #  already hasn't been added or it will result in redundant menus.

            if { [array size GUI::bondwires] == 0 || \
                 [lsearch [array names GUI::bondwires] $net] == -1 } {
                set GUI::bondwires($net) on
                $vm.bondwires add checkbutton -label "$net" \
                    -variable GUI::bondwires($net) -onvalue on -offvalue off \
                    -command  "GUI::Visibility bondwire-$net -mode toggle"
            }
        }
    }

    #  Draw Net Lines
    foreach nl $::netlines {
        foreach {net x1 y1 x2 y2} $nl {
            #puts [format "Net Line (%s) -- X1:  %s  Y1:  %s  X2:  %s  Y2:  %s" $net $x1 $y1 $x2 $y2]
            $cnvs create line $x1 $y1 $x2 $y2 -tags "netline netline-$net" -fill "cyan" -width 1

            #  Add bond wire to the View Bond Wires menu and make it visible
            #  Because a net can have more than one bond wire, need to ensure
            #  already hasn't been added or it will result in redundant menus.

            if { [array size GUI::netlines] == 0 || \
                 [lsearch [array names GUI::netlines] $net] == -1 } {
                set GUI::netlines($net) on
                $vm.netlines add checkbutton -label "$net" \
                    -variable GUI::netlines($net) -onvalue on -offvalue off \
                    -command  "GUI::Visibility netline-$net -mode toggle"
            }
        }
    }

    #$nlt configure -state disabled

    ##  Set an initial scale so the die is visible
    ##  This is an estimate based on trying a couple of
    ##  die files.

    set scaleX [expr ($::widgets(windowSizeX) / (2*$::die(width)) * $::ediu(ScaleFactor))]
    #puts [format "A:  %s  B:  %s  C:  %s" $scaleX $::widgets(windowSizeX) $::die(width)]
    if { $scaleX > 0 } {
        #zoom 1 0 0 
        set extents [$cnvs bbox all]
        #puts $extents
        #$cnvs create rectangle $extents -outline green
        #$cnvs create oval \
        #    [expr [lindex $extents 0]-2] [expr [lindex $extents 1]-2] \
        #    [expr [lindex $extents 0]+2] [expr [lindex $extents 1]+2] \
        #    -fill green
        #$cnvs create oval \
        #    [expr [lindex $extents 2]-2] [expr [lindex $extents 3]-2] \
        #    [expr [lindex $extents 2]+2] [expr [lindex $extents 3]+2] \
        #    -fill green
        #zoomMark $cnvs [lindex $extents 2] [lindex $extents 3]
        #zoomStroke $cnvs [lindex $extents 0] [lindex $extents 1]
        #zoomArea $cnvs [lindex $extents 0] [lindex $extents 1]

        #  Set the initial view
        GUI::View::Zoom $cnvs 25
    }

    #destroy $pb

    return $rv
}

#
#  ediuGraphicViewAddPin
#
proc ediuGraphicViewAddPin { x y pin net pad line_no { tags "diepad" } { color "yellow" } { outline "red" } { angle 0 } } {
    set cnvs $GUI::widgets(layoutview)
    set padtxt [expr {$pin == "-" ? $pad : $pin}]
    #puts [format "Pad Text:  %s (Pin:  %s  Pad:  %s" $padtxt $pin $pad]

    ##  Figure out the pad shape
    set shape [AIF::Pad::GetShape $pad]

    switch -regexp -- $shape {
        "SQ" -
        "SQUARE" {
            set pw [AIF::Pad::GetWidth $pad]
            $cnvs create rectangle [expr {$x-($pw/2.0)}] [expr {$y-($pw/2.0)}] \
                [expr {$x + ($pw/2.0)}] [expr {$y + ($pw/2.0)}] -outline $outline \
                -fill $color -tags "$tags" 

            #  Add text: Use pin number if it was supplied, otherwise pad name
            $cnvs create text $x $y -text $padtxt -fill $outline \
                -anchor center -font [list arial] -justify center \
                -tags "text padnumber padnumber-$pin $tags"
        }
        "CIRCLE" -
        "ROUND" {
            set pw [AIF::Pad::GetWidth $pad]
            $cnvs create oval [expr {$x-($pw/2.0)}] [expr {$y-($pw/2.0)}] \
                [expr {$x + ($pw/2.0)}] [expr {$y + ($pw/2.0)}] -outline $outline \
                -fill $color -tags "$tags" 

            #  Add text: Use pin number if it was supplied, otherwise pad name
            $cnvs create text $x $y -text $padtxt -fill $outline \
                -anchor center -font [list arial] -justify center \
                -tags "text padnumber padnumber-$pin $tags"
        }
        "OBLONG" -
        "OBROUND" {
            set pw [AIF::Pad::GetWidth $pad]
            set ph [AIF::Pad::GetHeight $pad]

            set x1 [expr $x-($pw/2.0)]
            set y1 [expr $y-($ph/2.0)]
            set x2 [expr $x+($pw/2.0)]
            set y2 [expr $y+($ph/2.0)]

            ##  An "oblong" pad is a rectangular pad with rounded ends.  The rounded
            ##  end is circular based on the width of the pad.  Ideally we'd draw this
            ##  as a single polygon but for now the pad is drawn with two round pads
            ##  connected by a rectangular pad.

            #  Compose the pad - it is four pieces:  Arc, Segment, Arc, Segment

            set padxy {}

            #  Top arc
            set arc [GUI::ArcPath [expr {$x-($pw/2.0)}] $y1 \
                [expr {$x + ($pw/2.0)}] [expr {$y1+$pw}] -start 180 -extent 180 -sides 20]
            foreach e $arc { lappend padxy $e }

            #  Bottom Arc
            set arc [GUI::ArcPath [expr {$x-($pw/2.0)}] \
                [expr {$y2-$pw}] [expr {$x + ($pw/2.0)}] $y2 -start 0 -extent 180 -sides 20]

            foreach e $arc { lappend padxy $e }

            set id [$cnvs create poly $padxy -outline $outline -fill $color -tags "$tags"]

            #  Add text: Use pin number if it was supplied, otherwise pad name
            $cnvs create text $x $y -text $padtxt -fill $outline \
                -anchor center -font [list arial] -justify center \
                -tags "text padnumber padnumber-$pin $tags"

            #  Handle any angle ajustment

            if { $angle != 0 } {
                set Ox $x
                set Oy $y

                set radians [expr {$angle * atan(1) * 4 / 180.0}] ;# Radians
                set xy {}
                foreach {x y} [$cnvs coords $id] {
                    # rotates vector (Ox,Oy)->(x,y) by angle clockwise

                    # Shift the object to the origin
                    set x [expr {$x - $Ox}]
                    set y [expr {$y - $Oy}]

                    #  Rotate the object
                    set xx [expr {$x * cos($radians) - $y * sin($radians)}]
                    set yy [expr {$x * sin($radians) + $y * cos($radians)}]

                    # Shift the object back to the original XY location
                    set xx [expr {$xx + $Ox}]
                    set yy [expr {$yy + $Oy}]

                    lappend xy $xx $yy
                }
                $cnvs coords $id $xy
            }
            
        }
        "RECT" -
        "RECTANGLE" {
            set pw [AIF::Pad::GetWidth $pad]
            set ph [AIF::Pad::GetHeight $pad]

            set x1 [expr $x-($pw/2.0)]
            set y1 [expr $y-($ph/2.0)]
            set x2 [expr $x+($pw/2.0)]
            set y2 [expr $y+($ph/2.0)]

            #puts [format "Pad extents:  X1:  %s  Y1:  %s  X2:  %s  Y2:  %s" $x1 $y1 $x2 $y2]

            $cnvs create rectangle $x1 $y1 $x2 $y2 -outline $outline -fill $color -tags "$tags $pad"

            #  Add text: Use pin number if it was supplied, otherwise pad name
            $cnvs create text $x $y -text $padtxt -fill $outline \
                -anchor center -font [list arial] -justify center \
                -tags "text padnumber padnumber-$pin $tags"
        }
        default {
            #error "Error parsing $filename (line: $line_no): $line"
            Transcript $::ediu(MsgWarning) [format "Skipping line %d in AIF file \"%s\"." $line_no $::ediu(filename)]
            #puts $line
        }
    }

    #$cnvs scale "pads" 0 0 100 100

    $cnvs configure -scrollregion [$cnvs bbox all]
}

#
#  ediuGraphicViewAddOutline
#
proc ediuGraphicViewAddOutline {} {
    set x2 [expr ($::die(width) / 2) * $::ediu(ScaleFactor)]
    set x1 [expr (-1 * $x2) * $::ediu(ScaleFactor)]
    set y2 [expr ($::die(height) / 2) * $::ediu(ScaleFactor)]
    set y1 [expr (-1 * $y2) * $::ediu(ScaleFactor)]

    set cnvs $GUI::widgets(layoutcview)
    $cnvs create rectangle $x1 $y1 $x2 $y2 -outline blue -tags "outline"

    #puts [format "Outline extents:  X1:  %s  Y1:  %s  X2:  %s  Y2:  %s" $x1 $y1 $x2 $y2]:w

    $cnvs configure -scrollregion [$cnvs bbox all]
}

#
#  ediuDrawPartOutline
#
proc ediuDrawPartOutline { name height width x y { color "green" } { tags "partoutline" } } {
    #puts [format "Part Outline input:  Name:  %s H:  %s  W:  %s  X:  %s  Y:  %s  C:  %s" $name $height $width $x $y $color]

    set x1 [expr $x-($width/2.0)]
    set x2 [expr $x+($width/2.0)]
    set y1 [expr $y-($height/2.0)]
    set y2 [expr $y+($height/2.0)]

    set cnvs $GUI::widgets(layoutview)
    $cnvs create rectangle $x1 $y1 $x2 $y2 -outline $color -tags "device device-$name $tags"
    $cnvs create text $x2 $y2 -text $name -fill $color \
        -anchor sw -font [list arial] -justify right -tags "text device device-$name refdes refdes-$name"

    #puts [format "Part Outline extents:  X1:  %s  Y1:  %s  X2:  %s  Y2:  %s" $x1 $y1 $x2 $y2]

    $cnvs configure -scrollregion [$cnvs bbox all]
}

#
#  ediuDrawBGAOutline
#
proc ediuDrawBGAOutline { { color "white" } } {
    set cnvs $GUI::widgets(layoutview)

    set x1 [expr -($::bga(width) / 2)]
    set x2 [expr +($::bga(width) / 2)]
    set y1 [expr -($::bga(height) / 2)]
    set y2 [expr +($::bga(height) / 2)]
    #puts [format "BGA Outline extents:  X1:  %s  Y1:  %s  X2:  %s  Y2:  %s" $x1 $y1 $x2 $y2]

    #  Does BGA section contain POLYGON outline?  If not, use the height and width
    if { [lsearch -exact [AIF::Variables BGA] OUTLINE] != -1 } {
        set poly [split [AIF::GetVar OUTLINE BGA]]
        set pw [lindex $poly 2]
        #puts $poly
        if { [lindex $poly 1] == 1 } {
            set points [lreplace $poly  0 3 ]
            #puts $points 
        } else {
            Transcript $::ediu(MsgWarning) "Only one polygon supported for BGA outline, reverting to derived outline."
            set x1 [expr -($::bga(width) / 2)]
            set x2 [expr +($::bga(width) / 2)]
            set y1 [expr -($::bga(height) / 2)]
            set y2 [expr +($::bga(height) / 2)]

            set points { $x1 $y1 $x2 $y2 }
        }


    } else {
        set points { $x1 $y1 $x2 $y2 }
    }

    $cnvs create polygon $points -outline $color -tags "$::bga(name) bga bgaoutline"
    $cnvs create text $x2 $y2 -text $::bga(name) -fill $color \
        -anchor sw -font [list arial] -justify right -tags "$::bga(name) bga text refdes"

    #  Add some text to note the corner XY coordinates - visual reference only
    $cnvs create text $x1 $y1 -text [format "X: %.2f  Y: %.2f" $x1 $y1] -fill $color \
        -anchor sw -font [list arial] -justify left -tags "guides dimension text"
    $cnvs create text $x1 $y2 -text [format "X: %.2f  Y: %.2f" $x1 $y2] -fill $color \
        -anchor nw -font [list arial] -justify left -tags "guides dimension text"
    $cnvs create text $x2 $y1 -text [format "X: %.2f  Y: %.2f" $x2 $y1] -fill $color \
        -anchor se -font [list arial] -justify left -tags "guides dimension text"
    $cnvs create text $x2 $y2 -text [format "X: %.2f  Y: %.2f" $x2 $y2] -fill $color \
        -anchor ne -font [list arial] -justify left -tags "guides dimension text"

    #  Add cross hairs through the origin - visual reference only
    $cnvs create line [expr $x1 - $::bga(width) / 4] 0 [expr $x2 +$::bga(width) / 4] 0 \
        -fill $color -dash . -tags "guides xyaxis"
    $cnvs create line 0 [expr $y1 - $::bga(height) / 4] 0 [expr $y2 +$::bga(height) / 4] \
        -fill $color -dash . -tags "guides xyaxis"

    $cnvs configure -scrollregion [$cnvs bbox all]
}

#
#  ediuAIFFileOpen
#
#  Open a AIF file, read the contents into the
#  Source View and update the appropriate status.
#
proc ediuAIFFileOpen { { f "" } } {
set zzz 0
    GUI::StatusBar::UpdateStatus -busy on
    ediuAIFInitialState

    ##  Set up the sections so they can be highlighted in the AIF source

    set sections {}
    set sectionRegExp ""
    foreach i [array names ::sections] {
        lappend sections $::sections($i)
        #puts $::sections($i)
        set sectionRegExp [format "%s%s%s%s%s%s%s" $sectionRegExp \
            [expr {$sectionRegExp == "" ? "(" : "|" }] \
            $::ediu(BackSlash) $::ediu(LeftBracket) $::sections($i) $::ediu(BackSlash) $::ediu(RightBracket) ]
    }

    set sectionRegExp [format "%s)" $sectionRegExp]

    set ignored {}
    set ignoreRegExp ""
    foreach i [array names ::ignored] {
        lappend ignored $::ignored($i)
        #puts $::ignored($i)
        set ignoreRegExp [format "%s%s%s%s%s%s%s" $ignoreRegExp \
            [expr {$ignoreRegExp == "" ? "(" : "|" }] \
            $::ediu(BackSlash) $::ediu(LeftBracket) $::ignored($i) $::ediu(BackSlash) $::ediu(RightBracket) ]
    }

    set ignoreRegExp [format "%s)" $ignoreRegExp]

    ##  Prompt the user for a file if not supplied

    if { $f != $::ediu(Nothing) } {
        set ::ediu(filename) $f
    } else {
        set ::ediu(filename) [ GUI::Dashboard::SelectAIFFile]
    }

    ##  Process the user supplied file
    if {$::ediu(filename) != $::ediu(Nothing) } {
        Transcript $::ediu(MsgNote) [format "Loading AIF file \"%s\"." $::ediu(filename)]
        set txt $GUI::widgets(sourceview)
        $txt configure -state normal
        $txt delete 1.0 end

        set f [open $::ediu(filename)]
        $txt insert end [read $f]
        Transcript $::ediu(MsgNote) [format "Scanning AIF file \"%s\" for sections." $::ediu(filename)]
        #ctext::addHighlightClass $txt diesections blue $sections
        ctext::addHighlightClassForRegexp $txt diesections blue $sectionRegExp
        ctext::addHighlightClassForRegexp $txt ignoredsections red $ignoreRegExp
        $txt highlight 1.0 end
        $txt configure -state disabled
        close $f
        Transcript $::ediu(MsgNote) [format "Loaded AIF file \"%s\"." $::ediu(filename)]

        ##  Parse AIF file

        AIF::Parse $::ediu(filename)
        Transcript $::ediu(MsgNote) [format "Parsed AIF file \"%s\"." $::ediu(filename)]

        ##  Load the DATABASE section ...

        if { [ AIF::Database::Section ] == -1 } {
            GUI::StatusBar::UpdateStatus -busy off
            return -1
        }

        ##  If the file a MCM-AIF file?

        if { $::ediu(MCMAIF) == 1 } {
            if { [ AIF::MCMDie::Section ] == -1 } {
                GUI::StatusBar::UpdateStatus -busy off
                return -1
            }
        }

        ##  Load the DIE section ...

        if { [ AIF::Die::Section ] == -1 } {
            GUI::StatusBar::UpdateStatus -busy off
            return -1
        }

        ##  Load the optional BGA section ...

        if { $::ediu(BGA) == 1 } {
            if { [ AIF::BGA::Section ] == -1 } {
                GUI::StatusBar::UpdateStatus -busy off
                return -1
            }
        }

        ##  Load the PADS section ...

        if { [ ediuAIFPadsSection ] == -1 } {
            GUI::StatusBar::UpdateStatus -busy off
            return -1
        }

        ##  Load the NETLIST section ...

        if { [ ediuAIFNetlistSection ] == -1 } {
            GUI::StatusBar::UpdateStatus -busy off
            return -1
        }

        ##  Draw the Graphic View

        ediuGraphicViewBuild
    } else {
        Transcript $::ediu(MsgWarning) "No AIF file selected."
    }

    GUI::StatusBar::UpdateStatus -busy off
}

#
#  ediuAIFFileClose
#
#  Close the AIF file and flush anything stored in
#  EDIU memory.  Clear the text widget for the source
#  view and the canvas widget for the graphic view.
#
proc ediuAIFFileClose {} {
    GUI::StatusBar::UpdateStatus -busy on
    Transcript $::ediu(MsgNote) [format "AIF file \"%s\" closed." $::ediu(filename)]
    ediuAIFInitialState
    GUI::StatusBar::UpdateStatus -busy off
}

#
#  ediuAIFInitialState
#
proc ediuAIFInitialState {} {

    ##  Put everything back into an initial state
    ediuAIFFileInit
    set ::ediu(filename) $::ediu(Nothing)

    ##  Remove all content from the AIF source view
    set txt $GUI::widgets(sourceview)
    $txt configure -state normal
    $txt delete 1.0 end
    $txt configure -state disabled

    ##  Remove all content from the (hidden) netlist text view
    set txt $GUI::widgets(netlistview)
    $txt configure -state normal
    $txt delete 1.0 end
    $txt configure -state disabled

    ##  Remove all content from the keyin netlist text view
    set txt $GUI::widgets(kynnetlistview)
    $txt configure -state normal
    $txt delete 1.0 end
    $txt configure -state disabled

    ##  Remove all content from the source graphic view
    set cnvs $GUI::widgets(layoutview)
    $cnvs delete all

    ##  Remove all content from the AIF Netlist table
    set nlt $GUI::widgets(netlisttable)
    $nlt delete 0 end

    ##  Clean up menus, remove dynamic content
    set vm $GUI::widgets(viewmenu)
    $vm.devices delete 3 end
    $vm.pads delete 3 end
}


#
#  ediuSparsePinsFileOpen
#
#  Open a Text file, read the contents into the
#  Source View and update the appropriate status.
#
proc ediuSparsePinsFileOpen {} {
    GUI::StatusBar::UpdateStatus -busy on

    ##  Prompt the user for a file
    ##set ::ediu(sparsepinsfile) [tk_getOpenFile -filetypes {{TXT .txt} {CSV .csv} {All *}}]
    set ::ediu(sparsepinsfile) [tk_getOpenFile -filetypes {{TXT .txt} {All *}}]

    ##  Process the user supplied file
    if {$::ediu(sparsepinsfile) == "" } {
        Transcript $::ediu(MsgWarning) "No Sparse Pins file selected."
    } else {
        Transcript $::ediu(MsgNote) [format "Loading Sparse Pins file \"%s\"." $::ediu(sparsepinsfile)]
        set txt $GUI::widgets(sparsepinsview)
        $txt configure -state normal
        $txt delete 1.0 end

        set f [open $::ediu(sparsepinsfile)]
        $txt insert end [read $f]
        Transcript $::ediu(MsgNote) [format "Scanning Sparse List \"%s\" for pin numbers." $::ediu(sparsepinsfile)]
        ctext::addHighlightClassForRegexp $txt sparsepinlist blue {[\t ]*[0-9][0-9]*[\t ]*$}
        $txt highlight 1.0 end
        $txt configure -state disabled
        close $f
        Transcript $::ediu(MsgNote) [format "Loaded Sparse Pins file \"%s\"." $::ediu(sparsepinsfile)]
        Transcript $::ediu(MsgNote) [format "Extracting Pin Numbers from Sparse Pins file \"%s\"." $::ediu(sparsepinsfile)]
        
        set pins [split $GUI::widgets(sparsepinsview) \n]
        set txt $GUI::widgets(sparsepinsview)
        set pins [split [$txt get 1.0 end] \n]

        set lc 1
        set ::ediu(sparsepinnames) {}
        set ::ediu(sparsepinnumbers) {}
 
        ##  Loop through the pin data and extract the pin names and numbers

        foreach i $pins {
            set pindata [regexp -inline -all -- {\S+} $i]
            if { [llength $pindata] == 0 } {
                continue
            } elseif { [llength $pindata] != 2 } {
                Transcript $::ediu(MsgWarning) [format "Skipping line %s, incorrect number of fields." $lc]
            } else {
                Transcript $::ediu(MsgNote) [format "Found Sparse Pin Number:  \"%s\" on line %s" [lindex $pindata 1] $lc]
                lappend ::ediu(sparsepinnames) [lindex $pindata 1]
                lappend ::ediu(sparsepinnumbers) [lindex $pindata 1]
                ##if { [incr lc] > 100 } { break }
            }

            incr lc
        }
    }

    # Force the scroll to the top of the sparse pins view
    $txt yview moveto 0
    $txt xview moveto 0

    GUI::StatusBar::UpdateStatus -busy off
}

#
#  ediuSparsePinsFileClose
#
#  Close the sparse rules file and flush anything stored
#  in EDIU memory.  Clear the text widget for the sparse
#  rules.
#
proc ediuSparsePinsFileClose {} {
    GUI::StatusBar::UpdateStatus -busy on
    Transcript $::ediu(MsgNote) [format "Sparse Pins file \"%s\" closed." $::ediu(sparsepinsfile)]
    set ::ediu(sparsepinsfile) $::ediu(Nothing)
    set txt $GUI::widgets(sparsepinsview)
    $txt configure -state normal
    $txt delete 1.0 end
    $txt configure -state disabled
    GUI::StatusBar::UpdateStatus -busy off
}

#
#  ediuSetupOpenPCB
#
proc ediuSetupOpenPCB { { f "" } } {
    GUI::StatusBar::UpdateStatus -busy on

    ##  Prompt the user for an Xpedition database

    if { $f != $::ediu(Nothing) } {
        set ::ediu(targetPath) $f
    } else {
        set ::ediu(targetPath) [tk_getOpenFile -filetypes {{PCB .pcb}}]
    }

    if {$::ediu(targetPath) == "" } {
        Transcript $::ediu(MsgWarning) "No Design File selected."
    } else {
        Transcript $::ediu(MsgNote) [format "Design File \"%s\" set as design target." $::ediu(targetPath)]
    }

    GUI::StatusBar::UpdateStatus -busy off
}

#
#  ediuSetupOpenLMC
#
proc ediuSetupOpenLMC { { f "" } } {
    GUI::StatusBar::UpdateStatus -busy on

    ##  Prompt the user for a Central Library database if not supplied

    if { $f != $::ediu(Nothing) } {
        set ::ediu(targetPath) $f
    } else {
        set ::ediu(targetPath) [tk_getOpenFile -filetypes {{LMC .lmc}}]
    }

    if {$::ediu(targetPath) == "" } {
        Transcript $::ediu(MsgWarning) "No Central Library selected."
    } else {
        Transcript $::ediu(MsgNote) [format "Central Library \"%s\" set as library target." $::ediu(targetPath)]
    }

    ##  Invoke the Cell Editor and open the LMC
    ##  Catch any exceptions raised by opening the database

    set errorCode [catch { MGC::OpenCellEditor } errorMessage]
    if {$errorCode != 0} {
        set ::ediu(targetPath) ""
        GUI::StatusBar::UpdateStatus -busy off
        return -code return 1
    }

    ##  Need to prompt for Cell partition

    puts "cellEdtrDb:  ------>$::ediu(cellEdtrDb)<-----"
    ##  Can't list partitions when application is visible so if it is,
    ##  hide it temporarily while the list of partitions is queried.

    set visbility $::ediu(appVisible)

    $::ediu(cellEdtr) Visible False
    set partitions [$::ediu(cellEdtrDb) Partitions]
    $::ediu(cellEdtr) Visible $visbility

    Transcript $::ediu(MsgNote) [format "Found %s cell %s." [$partitions Count] \
        [ediuPlural [$partitions Count] "partition"]]

    set ::ediu(cellEdtrPrtnNames) {}
    for {set i 1} {$i <= [$partitions Count]} {incr i} {
        set partition [$partitions Item $i]
        lappend ::ediu(cellEdtrPrtnNames) [$partition Name]
        Transcript $::ediu(MsgNote) [format "Found cell partition \"%s.\"" [$partition Name]]
    }
    
    MGC::CloseCellEditor

    ##  Invoke the PDB Editor and open the database
    ##  Catch any exceptions raised by opening the database

    set errorCode [catch { MGC::OpenPDBEditor } errorMessage]
    if {$errorCode != 0} {
        set ::ediu(targetPath) ""
        GUI::StatusBar::UpdateStatus -busy off
        return -code return 1
    }

    ##  Need to prompt for PDB partition

    set partitions [$::ediu(partEdtrDb) Partitions]

    Transcript $::ediu(MsgNote) [format "Found %s part %s." [$partitions Count] \
        [ediuPlural [$partitions Count] "partition"]]

    set ::ediu(partEdtrPrtnNames) {}
    for {set i 1} {$i <= [$partitions Count]} {incr i} {
        set partition [$partitions Item $i]
        lappend ::ediu(partEdtrPrtnNames) [$partition Name]
        Transcript $::ediu(MsgNote) [format "Found part partition \"%s.\"" [$partition Name]]
    }

    MGC::ClosePDBEditor

    GUI::StatusBar::UpdateStatus -busy off
}

#
#  ediuHelpAbout
#
proc ediuHelpAbout {} {
    tk_messageBox -type ok -message "$::ediu(EDIU)\nVersion 1.0" \
        -icon info -title "About"
}

#
#  ediuHelpVersion
#
proc ediuHelpVersion {} {
    tk_messageBox -type ok -message "$::ediu(EDIU)\nVersion 1.0" \
        -icon info -title "Version"
}

#
#  ediuNotImplemented
#
#  Stub procedure for GUI development to prevent Tcl and Tk errors.
#
proc ediuNotImplemented {} {
    tk_messageBox -type ok -icon info -message "This operation has not been implemented."
}

#
#  ediuUpdateStatus
#
#  Update the status panes with relevant informaiton.
#
proc ediuUpdateStatus-deprecated {mode} {
    if { $::ediu(connectMode) } {
        set ::widgets(mode) [format "Mode:  %s (Connect Mode)" $::ediu(mode)]
    } else {
        set ::widgets(mode) [format "Mode:  %s" $::ediu(mode)]
    }
    set ::widgets(AIFFile) [format "AIF File:  %-50s" $::ediu(filename)]

    ##  Need to determine what mode to update the target path widget
    if { $::ediu(mode) == $::ediu(designMode) } {
        set ::widgets(targetPath) [format "Design Path:  %-40s" $::ediu(targetPath)]
    } elseif { $::ediu(mode) == $::ediu(libraryMode) } {
        set ::widgets(targetPath) [format "Library Path:  %-40s" $::ediu(targetPath)]
    } else {
        set ::widgets(targetPath) [format "%-40s" "N/A"]
    }

    ##  Set the color of the status light
    set slf $GUI::widgets(statuslight)
    if { $mode == $::ediu(busy) } {
        $slf configure -background red
    } else {
        $slf configure -background green
    }

}

#
#  ediuAIFName
#
#  Scan the AIF source file for the "die_name" section
#
proc ediuAIFName {} {

    Transcript $::ediu(MsgNote) [format "Scanning AIF source for \"%s\"." $::sections(die)]

    set txt $GUI::widgets(sourceview)
    set dn [$txt search $::sections(die) 1.0 end]

    ##  Was the die found?

    if { $dn != $::ediu(Nothing)} {
        set dnl [lindex [split $dn .] 0]
        Transcript $::ediu(MsgNote) [format "Found section \"%s\" in AIF on line %s." $::sections(die) $dnl]

        ##  Need the text from the die line, drop the terminating semicolon
        set dnlt [$txt get $dnl.0 "$dnl.end - 1 chars"]

        ##  Extract the shape, height, and width from the dieShape
        set ::die(name) [lindex [split $dnlt] 1]
        set ::die(partition) [format "%s_die" $::die(name)]
        Transcript $::ediu(MsgNote) [format "Extracted die name (%s)." $::die(name)]
    } else {
        Transcript $::ediu(MsgError) [format "AIF does not contain section \"%s\"." $::sections(die)]
    }
}

#
#  ediuAIFBGASection
#
#  Scan the AIF source file for the "DIE" section
#
proc ediuAIFBGASection {} {
    ##  Make sure we have a BGA section!
    if { [lsearch -exact $::AIF::sections BGA] != -1 } {
        ##  Load the DIE section
        set vars [AIF::Variables BGA]

        foreach v $vars {
            #puts [format "-->  %s" $v]
            set ::bga([string tolower $v]) [AIF::GetVar $v BGA]
        }

        foreach i [array names ::bga] {
            Transcript $::ediu(MsgNote) [format "BGA \"%s\":  %s" [string toupper $i] $::bga($i)]
        }
    } else {
        Transcript $::ediu(MsgError) [format "AIF file \"%s\" does not contain a BGA section." $::ediu(filename)]
        return -1
    }
}

#
#  ediuAIFPadsSection
#
#  Scan the AIF source file for the "PADS" section
#
proc ediuAIFPadsSection {} {

    set rv 0
    set vm $GUI::widgets(viewmenu)
    $vm.pads add separator

    ##  Make sure we have a PADS section!
    if { [lsearch -exact $::AIF::sections PADS] != -1 } {
        ##  Load the PADS section
        set vars [AIF::Variables PADS]

        ##  Flush the pads dictionary

        set ::pads [dict create]
        set ::padtypes [dict create]

        ##  Populate the pads dictionary

        foreach v $vars {
            dict lappend ::pads $v [AIF::GetVar $v PADS]
            
            #  Add pad to the View Devices menu and make it visible
            set GUI::pads($v) on
            #$vm.pads add checkbutton -label "$v" -underline 0 \
            #    -variable GUI::pads($v) -onvalue on -offvalue off -command GUI::VisiblePad
            $vm.pads add checkbutton -label "$v" \
                -variable GUI::pads($v) -onvalue on -offvalue off \
                -command  "GUI::Visibility pad-$v -mode toggle"
        }

        foreach i [dict keys $::pads] {
            
            set padshape [lindex [regexp -inline -all -- {\S+} [lindex [dict get $::pads $i] 0]] 0]

            ##  Check units for legal option - AIF supports UM, MM, CM, INCH, MIL

            if { [lsearch -exact $::padshapes [string tolower $padshape]] == -1 } {
                Transcript $::ediu(MsgError) [format "Pad shape \"%s\" is not supported AIF syntax." $padshape]
                set rv -1
            } else {
                Transcript $::ediu(MsgNote) [format "Found pad \"%s\" with shape \"%s\"." [string toupper $i] $padshape]
            }
        }

        Transcript $::ediu(MsgNote) [format "AIF source file contains %d %s." [llength [dict keys $::pads]] [ediuPlural [llength [dict keys $::pads]] "pad"]]
    } else {
        Transcript $::ediu(MsgError) [format "AIF file \"%s\" does not contain a PADS section." $::ediu(filename)]
        set rv -1
    }

    return rv
}

#
#  ediuAIFNetlistSection
#
#  Scan the AIF source file for the "NETLIST" section
#
proc ediuAIFNetlistSection {} {
    set rv 0
    set txt $GUI::widgets(netlistview)

    ##  Make sure we have a NETLIST section!
    if { [lsearch -exact $::AIF::sections NETLIST] != -1 } {

        ##  Load the NETLIST section which was previously stored in the netlist text widget

        Netlist::Load

        Transcript $::ediu(MsgNote) [format "AIF source file contains %d net %s." [ Netlist::GetConnectionCount ] [ediuPlural [Netlist::GetConnectionCount] "connection"]]
        Transcript $::ediu(MsgNote) [format "AIF source file contains %d unique %s." [Netlist::GetNetCount] [ediuPlural [Netlist::GetNetCount] "net"]]
        
    } else {
        Transcript $::ediu(MsgError) [format "AIF file \"%s\" does not contain a NETLIST section." $::ediu(filename)]
        set rv -1
    }

    return rv
}

#
#  ediuPlural
#
proc ediuPlural { count txt } {
    if { $count == 1 } {
        return $txt
    } else {
        return [format "%ss" $txt]
    }
}

proc printArray { name } {
    upvar $name a
    foreach el [lsort [array names a]] {
        puts "$el = $a($el)"
    }
}

##  Main application

##  Figure out where the script lives
set pwd [pwd]
cd [file dirname [info script]]
variable IMPORTAIF [pwd]
cd $pwd

##  Load various pieces which comprise the application
foreach script { AIF.tcl Forms.tcl GUI.tcl MapEnum.tcl MGC.tcl Netlist.tcl } {
    source $IMPORTAIF/$script
}

console show
ediuInit
GUI::Build
GUI::StatusBar::UpdateStatus -busy off
#Transcript $::ediu(MsgNote) "$::ediu(EDIU) ready."
#ediuChooseCellPartitionDialog
#puts $retString
#set ::ediu(mode) $::ediu(libraryMode)
#ediuSetupOpenLMC "C:/Users/mike/Documents/Sandbox/Sandbox.lmc"
#set ::ediu(mode) $::ediu(designMode)
#ediuSetupOpenPCB "C:/Users/mike/Documents/a_simple_design_ee794/a_simple_design.pcb"
#catch { ediuAIFFileOpen "c:/users/mike/desktop/ImportAIF/data/Demo1.aif" } retString
#catch { ediuAIFFileOpen "c:/users/mike/desktop/ImportAIF/data/Demo4.aif" } retString
#catch { ediuAIFFileOpen "c:/users/mike/desktop/ImportAIF/data/MCMSampleC.aif" } retString
#catch { ediuAIFFileOpen "c:/users/mike/desktop/ImportAIF/data/BGA_w2_Dies.aif" } retString
##catch { ediuAIFFileOpen "c:/users/mike/desktop/ImportAIF/data/BGA_w2_Dies-2.aif" } retString
#catch { ediuAIFFileOpen "c:/users/mike/desktop/ImportAIF/data/BGA_w2_Dies-3.aif" } retString
catch { ediuAIFFileOpen "c:/users/mike/desktop/ImportAIF/data/Test2.aif" } retString
#GUI::Visibility text -all true -mode off
#set ::ediu(cellEdtrPrtnNames) { a b c d e f }
#ediuAIFFileOpen
