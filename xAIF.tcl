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
#    08/05/2014 - Major re-write of primary Tcl file to include namespace
#                 and elimination of plethora of global variables.
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
#  Initialize the xAIF namespace
#
namespace eval xAIF {
    variable Settings
    variable sections
    variable ignored
    variable widgets
    variable units
    variable padshapes

    ##
    ##  xAIF::Init
    ##
    proc Init {} {
        variable Settings

        ##  define variables in the xAIF namespace
        array unset Settings
        array set Settings {
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
            EDIU "Xpedition xAIF - AIF Import Utility"
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
        array unset xAIF::sections
        #array set xAIF::sections {
        #    die "die_name"
        #    padGeomName "pad_geom_name"
        #    padGeomShape "pad_geom_shape"
        #    dieActiveSize "die_active_size"
        #    dieSize "die_size"
        #    diePads "die_pads"
        #}

        ##  Sections within the AIF file
        array set xAIF::sections {
            database "DATABASE"
            die "DIE"
            diePads "PADS"
            netlist "NETLIST"
            bga "BGA"
            mcm_die "MCM_DIE"
        }

        array set xAIF::ignored {
            rings "RINGS"
            bondable_ring_area "BONDABLE_RING_AREA"
            wire "WIRE"
            fiducials "FIDUCIALS"
            die_logo "DIE_LOGO"
        }

        ##  Namespace array to store widgets
        array unset xAIF::widgets
        array set xAIF::widgets {
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
        set xAIF::Settings(mode) $xAIF::Settings(designMode)

        ##  Supported units
        set xAIF::units [list um mm cm inch mil]

        ##  Supported pad shapes
        set xAIF::padshapes [list circle round oblong obround rectangle rect square sq poly]

        ##  Initialize the AIF data structures
        GUI::File::Init
    }

    #
    #  HelpAbout
    #
    proc HelpAbout {} {
        tk_messageBox -type ok -message "$xAIF::Settings(EDIU)\nVersion 1.0" \
            -icon info -title "About"
    }

    #
    #  HelpVersion
    #
    proc HelpVersion {} {
        tk_messageBox -type ok -message "$xAIF::Settings(EDIU)\nVersion 1.0" \
            -icon info -title "Version"
    }

    #
    #  NotImplemented
    #
    #  Stub procedure for GUI development to prevent Tcl and Tk errors.
    #
    proc NotImplemented {} {
        tk_messageBox -type ok -icon info -message "This operation has not been implemented."
    }

    #
    #  UpdateStatus
    #
    #  Update the status panes with relevant informaiton.
    #
    proc UpdateStatus-deprecated {mode} {
        if { $xAIF::Settings(connectMode) } {
            set xAIF::widgets(mode) [format "Mode:  %s (Connect Mode)" $xAIF::Settings(mode)]
        } else {
            set xAIF::widgets(mode) [format "Mode:  %s" $xAIF::Settings(mode)]
        }
        set xAIF::widgets(AIFFile) [format "AIF File:  %-50s" $xAIF::Settings(filename)]

        ##  Need to determine what mode to update the target path widget
        if { $xAIF::Settings(mode) == $xAIF::Settings(designMode) } {
            set xAIF::widgets(targetPath) [format "Design Path:  %-40s" $xAIF::Settings(targetPath)]
        } elseif { $xAIF::Settings(mode) == $xAIF::Settings(libraryMode) } {
            set xAIF::widgets(targetPath) [format "Library Path:  %-40s" $xAIF::Settings(targetPath)]
        } else {
            set xAIF::widgets(targetPath) [format "%-40s" "N/A"]
        }

        ##  Set the color of the status light
        set slf $GUI::widgets(statuslight)
        if { $mode == $xAIF::Settings(busy) } {
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
    proc deprecated-ediuAIFName {} {

        GUI::Transcript -severity note -msg [format "Scanning AIF source for \"%s\"." $xAIF::sections(die)]

        set txt $GUI::widgets(sourceview)
        set dn [$txt search $xAIF::sections(die) 1.0 end]

        ##  Was the die found?

        if { $dn != $xAIF::Settings(Nothing)} {
            set dnl [lindex [split $dn .] 0]
            GUI::Transcript -severity note -msg [format "Found section \"%s\" in AIF on line %s." $xAIF::sections(die) $dnl]

            ##  Need the text from the die line, drop the terminating semicolon
            set dnlt [$txt get $dnl.0 "$dnl.end - 1 chars"]

            ##  Extract the shape, height, and width from the dieShape
            set xAIF::die(name) [lindex [split $dnlt] 1]
            set xAIF::die(partition) [format "%s_die" $::die(name)]
            GUI::Transcript -severity note -msg [format "Extracted die name (%s)." $::die(name)]
        } else {
            GUI::Transcript -severity error -msg [format "AIF does not contain section \"%s\"." $xAIF::sections(die)]
        }
    }

    #
    #  xAIF::Utility
    #
    namespace eval Utility {
        #
        #  xAIF::Utility::Plural
        #
        proc Plural { count txt } {
            if { $count == 1 } {
                return $txt
            } else {
                return [format "%ss" $txt]
            }
        }

        ##  xAIF::Utility::PrintArray
        proc PrintArray { name } {
            upvar $name a
            foreach el [lsort [array names a]] {
                puts "$el = $a($el)"
            }
        }
    }
}


##
##  Main application
##

##  Figure out where the script lives
set pwd [pwd]
cd [file dirname [info script]]
variable xAIF [pwd]
cd $pwd

##  Load various pieces which comprise the application
foreach script { AIF.tcl Forms.tcl GUI.tcl MapEnum.tcl MGC.tcl Netlist.tcl } {
    source $xAIF/$script
}

console show
xAIF::Init
GUI::Build
GUI::StatusBar::UpdateStatus -busy off
#GUI::Transcript -severity note -msg "$xAIF::Settings(EDIU) ready."
#ediuChooseCellPartitionDialog
#puts $retString
#set GUI::Dashboard::Mode $xAIF::Settings(libraryMode)
#GUI::Dashboard::SelectCentralLibrary "C:/Users/mike/Documents/Sandbox2/Sandbox2.lmc"
#set xAIF::Settings(mode) $xAIF::Settings(designMode)
#ediuSetupOpenPCB "C:/Users/mike/Documents/a_simple_design_ee794/a_simple_design.pcb"
#catch { ediuAIFFileOpen "c:/users/mike/desktop/ImportAIF/data/Demo1.aif" } retString
#catch { ediuAIFFileOpen "c:/users/mike/desktop/ImportAIF/data/Demo4.aif" } retString
#catch { ediuAIFFileOpen "c:/users/mike/desktop/ImportAIF/data/MCMSampleC.aif" } retString
#catch { ediuAIFFileOpen "c:/users/mike/desktop/ImportAIF/data/BGA_w2_Dies.aif" } retString
##catch { ediuAIFFileOpen "c:/users/mike/desktop/ImportAIF/data/BGA_w2_Dies-2.aif" } retString
#catch { ediuAIFFileOpen "c:/users/mike/desktop/ImportAIF/data/BGA_w2_Dies-3.aif" } retString
#catch { ediuAIFFileOpen "c:/users/mike/desktop/ImportAIF/data/Test2.aif" } retString
#catch { GUI::Dashboard::SelectAIFFile "c:/users/mike/desktop/ImportAIF/data/Test1.aif" } retString
#GUI::Visibility text -all true -mode off
#set xAIF::Settings(cellEdtrPrtnNames) { a b c d e f }
#ediuAIFFileOpen
