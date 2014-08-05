# vim: set expandtab tabstop=4 shiftwidth=4:
#
#  I like Vim (http://www.vim.org) as a text editor.  The above line
#  tells Vim to set the indent to 4 spaces and the tab key to indent
#  4 spaces.
# 
#  MGC.tcl
#
#  Tcl based Mentor Graphics Automation solution to Import an AIF file and
#  generate Pad, Padstack, Cell, and PDB to be used in a IC Package design.
#  This script should be run with "wish" or "tclsh" - it cannot be dragged
#  onto LM.
#
#  This script requires Tcl 8.4.20.  Tcl 8.5.x and 8.6.x are not supported
#  by the Mentor Graphics COM API interface.  You can download Tcl 8.4.20
#  from ActiveState.com:
#
#    http://www.activestate.com/activetcl/downloads
#
#
#  (c) July 2014 - Mentor Graphics Corporation
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
#    07/21/2014 - Initial version.  Moved interaction with Mentor tools
#                 to separate file and namespace to ease code maintenance.
#

##
##  Define the MGC namespace and procedure supporting operations
##
namespace eval MGC {
    #
    #  Open Expedition, open the database, handle licensing.
    #
    proc OpenExpedition {} {
        #  Crank up Expedition

        if { $::ediu(connectMode) } {
            GUI::Transcript -severity note -msg "Connecting to existing Expedition session."
            set ::ediu(pcbApp) [::tcom::ref getactiveobject "MGCPCB.ExpeditionPCBApplication"]

            #  Use the active PCB document object
            set errorCode [catch {set ::ediu(pcbDoc) [$::ediu(pcbApp) ActiveDocument] } errorMessage]
            if {$errorCode != 0} {
                GUI::Transcript -severity error -msg [format "API error \"%s\", build aborted." $errorMessage]
                return -code return 1
            }
        } else {
            GUI::Transcript -severity note -msg "Opening Expedition."
            set ::ediu(pcbApp) [::tcom::ref createobject "MGCPCB.ExpeditionPCBApplication"]

            # Open the database
            GUI::Transcript -severity note -msg "Opening database for Expedition."

            #  Create a PCB document object
            set errorCode [catch {set ::ediu(pcbDoc) [$::ediu(pcbApp) \
                OpenDocument $::ediu(targetPath)] } errorMessage]
            if {$errorCode != 0} {
                GUI::Transcript -severity error -msg [format "API error \"%s\", build aborted." $errorMessage]
                return -code return 1
            }
        }

        #  Turn off trivial dialog boxes - makes batch operations smoother
        [$::ediu(pcbApp) Gui] SuppressTrivialDialogs True

        #  Set application visibility
        $::ediu(pcbApp) Visible $::ediu(appVisible)

        #  Ask Expedition document for the key
        set key [$::ediu(pcbDoc) Validate "0" ] 

        #  Get token from license server
        set licenseServer [::tcom::ref createobject "MGCPCBAutomationLicensing.Application"]

        set licenseToken [ $licenseServer GetToken $key ] 

        #  Ask the document to validate the license token
        $::ediu(pcbDoc) Validate $licenseToken  
        #$pcbApp LockServer False
        #  Suppress trivial dialog boxes
        #[$::ediu(pcbDoc) Gui] SuppressTrivialDialogs True

        set ::ediu(targetPath) [$::ediu(pcbDoc) Path][$::ediu(pcbDoc) Name]
        set GUI::Dashboard::DesignPath [$::ediu(pcbDoc) Path][$::ediu(pcbDoc) Name]
        #puts [$::ediu(pcbDoc) Path][$::ediu(pcbDoc) Name]
        GUI::Transcript -severity note -msg [format "Connected to design database:  %s%s" \
            [$::ediu(pcbDoc) Path] [$::ediu(pcbDoc) Name]]
    }

    #
    #  Open the Padstack Editor
    #
    proc OpenPadstackEditor { { mode "-opendatabase" } } {
        #  Crank up the Padstack Editor once per sessions

        GUI::Transcript -severity note -msg [format "Opening Padstack Editor in %s mode." $GUI::Dashboard::Mode]

        ##  Which mode?  Design or Library?
        if { $GUI::Dashboard::Mode == $::ediu(designMode) } {
            ##  Invoke Expedition on the design so the Padstack Editor can be started
            ##  Catch any exceptions raised by opening the database

            ##  Is Expedition already open?  It will be if the Padstack Editor
            ##  is called as part of building a Cell.  In this case, there is no
            ##  reason to reopen Expedition as it will end up in read-only mode.

            if { $mode == "-opendatabase" } {
                set errorCode [catch { MGC::OpenExpedition } errorMessage]
                if {$errorCode != 0} {
                    GUI::Transcript -severity error -msg [format "API error \"%s\", build aborted." $errorMessage]
                    GUI::StatusBar::UpdateStatus -busy off
                    return
                }
            } else {
                GUI::Transcript -severity note -msg "Reusing previously opened instance of Expedition."
            }
            set ::ediu(pdstkEdtr) [$::ediu(pcbDoc) PadstackEditor]
            set ::ediu(pdstkEdtrDb) [$::ediu(pdstkEdtr) ActiveDatabase]
        } elseif { $GUI::Dashboard::Mode == $::ediu(libraryMode) } {
            set ::ediu(pdstkEdtr) [::tcom::ref createobject "MGCPCBLibraries.PadstackEditorDlg"]
            # Open the database
            set errorCode [catch {set ::ediu(pdstkEdtrDb) [$::ediu(pdstkEdtr) \
                OpenDatabaseEx $::ediu(targetPath) false] } errorMessage]
            if {$errorCode != 0} {
                GUI::Transcript -severity error -msg [format "API error \"%s\", build aborted." $errorMessage]
                return -code return 1
            }
        } else {
            GUI::Transcript -severity error -msg "Mode not set, build aborted."
            return -code return 1
        }

        # Lock the server
        set errorCode [catch { $::ediu(pdstkEdtr) LockServer } errorMessage]
        if {$errorCode != 0} {
            GUI::Transcript -severity error -msg [format "API error \"%s\", build aborted." $errorMessage]
            return -code return 1
        }

        # Display the dialog box?  Note this isn't necessary
        # but done for clarity and useful for debugging purposes.
        $::ediu(pdstkEdtr) Visible $::ediu(appVisible)
    }

    #
    #  Close Padstack Editor Lib
    #
    proc ClosePadstackEditor { { mode "-closedatabase" } } {
        ##  Which mode?  Design or Library?

        if { $GUI::Dashboard::Mode == $::ediu(designMode) } {
            GUI::Transcript -severity note -msg "Closing database for Padstack Editor."
            set errorCode [catch { $::ediu(pdstkEdtr) UnlockServer } errorMessage]
            if {$errorCode != 0} {
                GUI::Transcript -severity error -msg [format "API error \"%s\", build aborted." $errorMessage]
                return -code return 1
            }
            GUI::Transcript -severity note -msg "Closing Padstack Editor."
            ##  Close Padstack Editor
            $::ediu(pdstkEdtr) SaveActiveDatabase
            $::ediu(pdstkEdtr) Quit
            ##  Close the Expedition Database

            ##  May want to leave Expedition and the database open ...
            #if { $mode == "-closedatabase" } {
            #    $::ediu(pcbDoc) Save
            #    $::ediu(pcbDoc) Close
            #    ##  Close Expedition
            #    $::ediu(pcbApp) Quit
            #}
            if { !$::ediu(connectMode) } {
                ##  Close the Expedition Database and terminate Expedition
                $::ediu(pcbDoc) Close
                ##  Close Expedition
                $::ediu(pcbApp) Quit
            }
        } elseif { $GUI::Dashboard::Mode == $::ediu(libraryMode) } {
            GUI::Transcript -severity note -msg "Closing database for Padstack Editor."
            set errorCode [catch { $::ediu(pdstkEdtr) UnlockServer } errorMessage]
            if {$errorCode != 0} {
                GUI::Transcript -severity error -msg [format "API error \"%s\", build aborted." $errorMessage]
                return -code return 1
            }
            $::ediu(pdstkEdtr) CloseActiveDatabase True
            GUI::Transcript -severity note -msg "Closing Padstack Editor."
            $::ediu(pdstkEdtr) Quit
        } else {
            GUI::Transcript -severity error -msg "Mode not set, build aborted."
            return -code return 1
        }
    }

    #
    #  Open the Cell Editor
    #
    proc OpenCellEditor { } {
        ##  Which mode?  Design or Library?
        if { $GUI::Dashboard::Mode == $::ediu(designMode) } {
puts "QQQ"
            ##  Invoke Expedition on the design so the Cell Editor can be started
            ##  Catch any exceptions raised by opening the database
            set errorCode [catch { MGC::OpenExpedition } errorMessage]
            if {$errorCode != 0} {
                GUI::Transcript -severity error -msg [format "API error \"%s\", build aborted." $errorMessage]
                GUI::StatusBar::UpdateStatus -busy off
                return
            }
            set ::ediu(cellEdtr) [$::ediu(pcbDoc) CellEditor]
            GUI::Transcript -severity note -msg "Using design database for Cell Editor."
            set ::ediu(cellEdtrDb) [$::ediu(cellEdtr) ActiveDatabase]
        } elseif { $GUI::Dashboard::Mode == $::ediu(libraryMode) } {
puts "ZZZ"
            set ::ediu(cellEdtr) [::tcom::ref createobject "CellEditorAddin.CellEditorDlg"]
            set ::ediu(pdstkEdtr) [::tcom::ref createobject "MGCPCBLibraries.PadstackEditorDlg"]
            # Open the database
            GUI::Transcript -severity note -msg "Opening library database for Cell Editor."

            set errorCode [catch {set ::ediu(cellEdtrDb) [$::ediu(cellEdtr) \
                OpenDatabase $::ediu(targetPath) false] } errorMessage]
            if {$errorCode != 0} {
                GUI::Transcript -severity error -msg [format "API error \"%s\", build aborted." $errorMessage]
                return -code return 1
            }
        } else {
            GUI::Transcript -severity error -msg "Mode not set, build aborted."
            return -code return 1
        }

        #set ::ediu(cellEdtrDb) [$::ediu(cellEdtr) OpenDatabase $::ediu(targetPath) false]
        set errorCode [catch { $::ediu(cellEdtr) LockServer } errorMessage]
        if {$errorCode != 0} {
            GUI::Transcript -severity error -msg [format "API error \"%s\", build aborted." $errorMessage]
            return -code return 1
        }

        # Display the dialog box?  Note this isn't necessary
        # but done for clarity and useful for debugging purposes.
        $::ediu(cellEdtr) Visible $::ediu(appVisible)
    }

    #
    #  Close Cell Editor Lib
    #
    proc CloseCellEditor {} {
        ##  Which mode?  Design or Library?

        if { $GUI::Dashboard::Mode == $::ediu(designMode) } {
            GUI::Transcript -severity note -msg "Closing database for Cell Editor."
            set errorCode [catch { $::ediu(cellEdtr) UnlockServer } errorMessage]
            if {$errorCode != 0} {
                GUI::Transcript -severity error -msg [format "API error \"%s\", build aborted." $errorMessage]
                return -code return 1
            }
            GUI::Transcript -severity note -msg "Closing Cell Editor."
            ##  Close Padstack Editor
            set errorCode [catch { $::ediu(cellEdtr) SaveActiveDatabase } errorMessage]
            if {$errorCode != 0} {
                GUI::Transcript -severity error -msg [format "API error \"%s\", build aborted." $errorMessage]
                return -code return 1
            }
            #$::ediu(cellEdtr) SaveActiveDatabase
            $::ediu(cellEdtr) Quit

            ##  Save the Expedition Database
            $::ediu(pcbDoc) Save

            if { !$::ediu(connectMode) } {
                ##  Close the Expedition Database and terminate Expedition
                $::ediu(pcbDoc) Close
                ##  Close Expedition
                $::ediu(pcbApp) Quit
            }
        } elseif { $GUI::Dashboard::Mode == $::ediu(libraryMode) } {
            GUI::Transcript -severity note -msg "Closing database for Cell Editor."
            set errorCode [catch { $::ediu(cellEdtr) UnlockServer } errorMessage]
            if {$errorCode != 0} {
                GUI::Transcript -severity error -msg [format "API error \"%s\", build aborted." $errorMessage]
                return -code return 1
            }
            $::ediu(cellEdtr) CloseActiveDatabase True
            GUI::Transcript -severity note -msg "Closing Cell Editor."
            $::ediu(cellEdtr) Quit
        } else {
            GUI::Transcript -severity error -msg "Mode not set, build aborted."
            return -code return 1
        }
    }

    #
    #  Open the PDB Editor
    #
    proc OpenPDBEditor {} {
        ##  Which mode?  Design or Library?
        if { $GUI::Dashboard::Mode == $::ediu(designMode) } {
            ##  Invoke Expedition on the design so the PDB Editor can be started
            ##  Catch any exceptions raised by opening the database
            set errorCode [catch { MGC::OpenExpedition } errorMessage]
            if {$errorCode != 0} {
                GUI::Transcript -severity error -msg [format "API error \"%s\", build aborted." $errorMessage]
                GUI::StatusBar::UpdateStatus -busy off
                return
            }
            set ::ediu(partEdtr) [$::ediu(pcbDoc) PartEditor]
            GUI::Transcript -severity note -msg "Using design database for PDB Editor."
            set ::ediu(partEdtrDb) [$::ediu(partEdtr) ActiveDatabase]
        } elseif { $GUI::Dashboard::Mode == $::ediu(libraryMode) } {
            set ::ediu(partEdtr) [::tcom::ref createobject "MGCPCBLibraries.PartsEditorDlg"]
            # Open the database
            GUI::Transcript -severity note -msg "Opening library database for PDB Editor."

            set errorCode [catch {set ::ediu(partEdtrDb) [$::ediu(partEdtr) \
                OpenDatabaseEx $::ediu(targetPath) false] } errorMessage]
            if {$errorCode != 0} {
                GUI::Transcript -severity error -msg [format "API error \"%s\", build aborted." $errorMessage]
                return -code return 1
            }
            puts "22->  $errorCode"
            puts "33->  $errorMessage"
        } else {
            GUI::Transcript -severity error -msg "Mode not set, build aborted."
            return -code return 1
        }
puts "OpenPDBEdtr - 1"

        #set ::ediu(partEdtrDb) [$::ediu(partEdtr) OpenDatabase $::ediu(targetPath) false]
        set errorCode [catch { $::ediu(partEdtr) LockServer } errorMessage]
        if {$errorCode != 0} {
            GUI::Transcript -severity error -msg [format "API error \"%s\", build aborted." $errorMessage]
            return -code return 1
        }
            puts "44->  $errorCode"
            puts "55->  $errorMessage"

        # Display the dialog box?  Note this isn't necessary
        # but done for clarity and useful for debugging purposes.
        $::ediu(partEdtr) Visible $::ediu(appVisible)

        #return -code return 0
    }

    #
    #  Close PDB Editor Lib
    #
    proc ClosePDBEditor { } {
        ##  Which mode?  Design or Library?

        if { $GUI::Dashboard::Mode == $::ediu(designMode) } {
            GUI::Transcript -severity note -msg "Closing database for PDB Editor."
            set errorCode [catch { $::ediu(partEdtr) UnlockServer } errorMessage]
            if {$errorCode != 0} {
                GUI::Transcript -severity error -msg [format "API error \"%s\", build aborted." $errorMessage]
                return -code return 1
            }
            GUI::Transcript -severity note -msg "Closing PDB Editor."
            ##  Close Padstack Editor
            $::ediu(partEdtr) SaveActiveDatabase
            $::ediu(partEdtr) Quit
            ##  Close the Expedition Database
            ##  Need to save?
            if { [$::ediu(pcbDoc) IsSaved] == "False" } {
                $::ediu(pcbDOc) Save
            }
            #$::ediu(pcbDoc) Save
            #$::ediu(pcbDoc) Close
            ##  Close Expedition
            #$::ediu(pcbApp) Quit

            if { !$::ediu(connectMode) } {
                ##  Close the Expedition Database and terminate Expedition
                $::ediu(pcbDoc) Close
                ##  Close Expedition
                $::ediu(pcbApp) Quit
            }
        } elseif { $GUI::Dashboard::Mode == $::ediu(libraryMode) } {
            GUI::Transcript -severity note -msg "Closing database for PDB Editor."
            set errorCode [catch { $::ediu(partEdtr) UnlockServer } errorMessage]
            if {$errorCode != 0} {
                GUI::Transcript -severity error -msg [format "API error \"%s\", build aborted." $errorMessage]
                return -code return 1
            }
            $::ediu(partEdtr) CloseActiveDatabase True
            GUI::Transcript -severity note -msg "Closing PDB Editor."
            $::ediu(partEdtr) Quit
        } else {
            GUI::Transcript -severity error -msg "Mode not set, build aborted."
            return -code return 1
        }
    }

    ##
    ##  MGC::SetupLMC
    ##
    proc SetupLMC { { f "" } } {
        GUI::StatusBar::UpdateStatus -busy on

        ##  Prompt the user for a Central Library database if not supplied

        if { $f != $::ediu(Nothing) } {
            set ::ediu(targetPath) $f
        } else {
            set ::ediu(targetPath) [tk_getOpenFile -filetypes {{LMC .lmc}}]
        }

        if {$::ediu(targetPath) == "" } {
            GUI::Transcript -severity warning -msg "No Central Library selected."
        } else {
            GUI::Transcript -severity note -msg [format "Central Library \"%s\" set as library target." $::ediu(targetPath)]
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

        GUI::Transcript -severity note -msg [format "Found %s cell %s." [$partitions Count] \
            [ediuPlural [$partitions Count] "partition"]]

        set ::ediu(cellEdtrPrtnNames) {}
        for {set i 1} {$i <= [$partitions Count]} {incr i} {
            set partition [$partitions Item $i]
            lappend ::ediu(cellEdtrPrtnNames) [$partition Name]
            GUI::Transcript -severity note -msg [format "Found cell partition \"%s.\"" [$partition Name]]
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

        GUI::Transcript -severity note -msg [format "Found %s part %s." [$partitions Count] \
            [ediuPlural [$partitions Count] "partition"]]

        set ::ediu(partEdtrPrtnNames) {}
        for {set i 1} {$i <= [$partitions Count]} {incr i} {
            set partition [$partitions Item $i]
            lappend ::ediu(partEdtrPrtnNames) [$partition Name]
            GUI::Transcript -severity note -msg [format "Found part partition \"%s.\"" [$partition Name]]
        }

        MGC::ClosePDBEditor

        GUI::StatusBar::UpdateStatus -busy off
    }


    ##
    ##  Define the Generate namespace and procedure supporting operations
    ##
    namespace eval Generate {
        #
        #  MGC::Generate::Pad
        #
        #  Pads are interesting in that can't simply be updated.  To change a pad
        #  it must be deleted and then replaced.  A pad can't be deleted if it is
        #  referenced by a padstack so that scenario must be handled.
        #
        proc Pad { { mode "-replace" } } {
            GUI::StatusBar::UpdateStatus -busy on
            set ::ediu(sTime) [clock format [clock seconds] -format "%m/%d/%Y %T"]

            ##  Make sure a Target library or design has been defined

            if {$::ediu(targetPath) == $::ediu(Nothing) && $::ediu(connectMode) != True } {
                if {$GUI::Dashboard::Mode == $::ediu(designMode)} {
                    GUI::Transcript -severity error -msg "No Design (PCB) specified, build aborted."
                } elseif {$GUI::Dashboard::Mode == $::ediu(libraryMode)} {
                    GUI::Transcript -severity error -msg "No Central Library (LMC) specified, build aborted."
                } else {
                    GUI::Transcript -severity error -msg "Mode not set, build aborted."
                }

                GUI::StatusBar::UpdateStatus -busy off
                return
            }

            ##  Rudimentary error checking - need a name, shape, height, and width!

            if { $::padGeom(name) == "" || $::padGeom(shape) == "" || \
                $::padGeom(height) == "" || $::padGeom(width) == "" } {
                GUI::Transcript -severity error -msg "Incomplete pad definition, build aborted."
                GUI::StatusBar::UpdateStatus -busy off
                return
            }

            ##  Map the shape to something we can pass through the API

            set shape [MapEnum::Shape $::padGeom(shape)]

            if { $shape == $::ediu(Nothing) } {
                GUI::Transcript -severity error -msg "Unsupported pad shape, build aborted."
                GUI::StatusBar::UpdateStatus -busy off
                return
            }

            ##  Define a pad name based on the shape, height and width
            set padName [format "%s %sx%s" $::padGeom(shape) $::padGeom(height) $::padGeom(width)]

            ##  Invoke the Padstack Editor and open the target
            ##  Catch any exceptions raised by opening the database
            set errorCode [catch { MGC::OpenPadstackEditor } errorMessage]
            if {$errorCode != 0} {
                GUI::Transcript -severity error -msg [format "API error \"%s\", build aborted." $errorMessage]
                GUI::StatusBar::UpdateStatus -busy off
                return
            }

            #  Does the pad exist?

            set oldPadName [$::ediu(pdstkEdtrDb) FindPad $padName]
            #puts "Old Pad Name:  ----->$oldPadName<>$padName<-------"

            #  Echo some information about what will happen.

            if {$oldPadName == $::ediu(Nothing)} {
                GUI::Transcript -severity note -msg [format "Pad \"%s\" does not exist." $padName]
            } elseif {$mode == "-replace" } {
                GUI::Transcript -severity warning -msg [format "Pad \"%s\" already exists and will be replaced." $padName]

                ##  Can't delete a pad that is referenced by a padstack so
                ##  need to catch the error if it is raised by the API.
                set errorCode [catch { $oldPadName Delete } errorMessage]
                if {$errorCode != 0} {
                    GUI::Transcript -severity error -msg [format "API error \"%s\", build aborted." $errorMessage]
                    MGC::ClosePadstackEditor
                    GUI::StatusBar::UpdateStatus -busy off
                    return
                }
            } else {
                GUI::Transcript -severity warning -msg [format "Pad \"%s\" already exists and will not be replaced." $padName]
                MGC::ClosePadstackEditor
                GUI::StatusBar::UpdateStatus -busy off
                return
            }

            ##  Ready to build a new pad
            set newPad [$::ediu(pdstkEdtrDb) NewPad]

            $newPad -set Name $padName
            #puts "------>$padName<----------"
            $newPad -set Shape [expr $shape]
            $newPad -set Width \
                [expr [MapEnum::Units $::database(units) "pad"]] [expr $::padGeom(width)]
            $newPad -set Height \
                [expr [MapEnum::Units $::database(units) "pad"]] [expr $::padGeom(height)]
            $newPad -set OriginOffsetX \
                [expr [MapEnum::Units $::database(units) "pad"]] [expr $::padGeom(offsetx)]
            $newPad -set OriginOffsetY \
                [expr [MapEnum::Units $::database(units) "pad"]] [expr $::padGeom(offsety)]

            GUI::Transcript -severity note -msg [format "Committing pad:  %s" $padName]
            $newPad Commit

            MGC::ClosePadstackEditor

            ##  Report some time statistics
            set ::ediu(cTime) [clock format [clock seconds] -format "%m/%d/%Y %T"]
            GUI::Transcript -severity note -msg [format "Start Time:  %s" $::ediu(sTime)]
            GUI::Transcript -severity note -msg [format "Completion Time:  %s" $::ediu(cTime)]

            GUI::StatusBar::UpdateStatus -busy off
        }

        #
        #  MGC::Generate::Padstack
        #
        proc Padstack { { mode "-replace" } } {
            GUI::StatusBar::UpdateStatus -busy on
            set ::ediu(sTime) [clock format [clock seconds] -format "%m/%d/%Y %T"]

            ##  Extract pad details from AIF file

            ##  Make sure a Target library or design has been defined

            if {$::ediu(targetPath) == $::ediu(Nothing) && $::ediu(connectMode) != True } {
                if {$GUI::Dashboard::Mode == $::ediu(designMode)} {
                    GUI::Transcript -severity error -msg "No Design (PCB) specified, build aborted."
                } elseif {$GUI::Dashboard::Mode == $::ediu(libraryMode)} {
                    GUI::Transcript -severity error -msg "No Central Library (LMC) specified, build aborted."
                } else {
                    GUI::Transcript -severity error -msg "Mode not set, build aborted."
                }

                GUI::StatusBar::UpdateStatus -busy off
                return
            }

            ##  Rudimentary error checking - need a name, shape, height, and width!

            if { $::padGeom(name) == "" || $::padGeom(shape) == "" || \
                $::padGeom(height) == "" || $::padGeom(width) == "" } {
                GUI::Transcript -severity error -msg "Incomplete pad definition, build aborted."
                GUI::StatusBar::UpdateStatus -busy off
                return
            }

            ##  Define a pad name based on the shape, height and width
            set padName [format "%s %sx%s" $::padGeom(shape) $::padGeom(height) $::padGeom(width)]

            ##  Invoke the Padstack Editor and open the target
            ##  Catch any exceptions raised by opening the database
            set errorCode [catch { MGC::OpenPadstackEditor } errorMessage]
            if {$errorCode != 0} {
                GUI::Transcript -severity error -msg [format "API error \"%s\", build aborted." $errorMessage]
                GUI::StatusBar::UpdateStatus -busy off
                return
            }

            #  Look for the pad that the AIF references
            set pad [$::ediu(pdstkEdtrDb) FindPad $padName]

            if {$pad == $::ediu(Nothing)} {
                GUI::Transcript -severity error -msg [format "Pad \"%s\" is not defined, padstack \"%s\" build aborted." $padName $::padGeom(name)]
                GUI::StatusBar::UpdateStatus -busy off
                return
            }

            #  Does the pad exist?

            set oldPadstackName [$::ediu(pdstkEdtrDb) FindPadstack $::padGeom(name)]

            #  Echo some information about what will happen.

            if {$oldPadstackName == $::ediu(Nothing)} {
                GUI::Transcript -severity note -msg [format "Padstack \"%s\" does not exist." $padName]
            } elseif {$mode == "-replace" } {
                GUI::Transcript -severity warning -msg [format "Padstack \"%s\" already exists and will be replaced." $::padGeom(name)]
                ##  Can't delete a padstack that is referenced by a padstack
                ##  so need to catch the error if it is raised by the API.
                set errorCode [catch { $oldPadstackName Delete } errorMessage]
                if {$errorCode != 0} {
                    GUI::Transcript -severity error -msg [format "API error \"%s\", build aborted." $errorMessage]
                    MGC::ClosePadstackEditor
                    GUI::StatusBar::UpdateStatus -busy off
                    return
                }
            } else {
                GUI::Transcript -severity warning -msg [format "Padstack \"%s\" already exists and will not be replaced." $::padGeom(name)]
                MGC::ClosePadstackEditor
                GUI::StatusBar::UpdateStatus -busy off
                return
            }

            ##  Ready to build the new padstack
            set newPadstack [$::ediu(pdstkEdtrDb) NewPadstack]

            $newPadstack -set Name $::padGeom(name)

            ##  Need to handle various pad types which are inferred while processing
            ##  the netlist.  If for some reason the pad doesn't appear in the netlist

            if { ![dict exist $::padtypes $::padGeom(name)] } {
                dict lappend ::padtypes $::padGeom(name) "diepad"
            }

            switch -exact [dict get $::padtypes $::padGeom(name)] {
                "bondpad" {
                    $newPadstack -set Type $::PadstackEditorLib::EPsDBPadstackType(epsdbPadstackTypeBondPin)
                }
                "ballpad" {
                    $newPadstack -set Type $::PadstackEditorLib::EPsDBPadstackType(epsdbPadstackTypePinSMD)
                }
                "diepad" {
                    $newPadstack -set Type $::PadstackEditorLib::EPsDBPadstackType(epsdbPadstackTypePartStackPin)
                }
                default {
                    $newPadstack -set Type $::PadstackEditorLib::EPsDBPadstackType(epsdbPadstackTypePinSMD)
                }
            }

            #$newPadstack -set PinClass $::MGCPCB::EPcbPinClassType(epcbPinClassDie)

            $newPadstack -set Pad \
                [expr $::PadstackEditorLib::EPsDBPadLayer(epsdbPadLayerTopMount)] $pad
            $newPadstack -set Pad \
                [expr $::PadstackEditorLib::EPsDBPadLayer(epsdbPadLayerBottomMount)] $pad

            $newPadstack Commit

            MGC::ClosePadstackEditor

            ##  Report some time statistics
            set ::ediu(cTime) [clock format [clock seconds] -format "%m/%d/%Y %T"]
            GUI::Transcript -severity note -msg [format "Start Time:  %s" $::ediu(sTime)]
            GUI::Transcript -severity note -msg [format "Completion Time:  %s" $::ediu(cTime)]

            GUI::StatusBar::UpdateStatus -busy off
        }

        #
        #  MGC::Generate::Cell
        #
        proc Cell { device args } {
            ##  Process command arguments
            array set V [list -partition $GUI::Dashboard::CellPartition -mirror none] ;# Default values
            foreach {a value} $args {
                if {! [info exists V($a)]} {error "unknown option $a"}
                if {$value == {}} {error "value of \"$a\" missing"}
                if { [string compare $a -mirror] } {
                    set V($a) [string tolower $value]
                } else {
                    set V($a) $value
                }
            }

            set ::ediu(cellEdtrPrtnName) $V(-partition)

            ##  Check mirror option, make sure it is valid
            if { [lsearch [list none x y xy] $V(-mirror)] == -1 } {
                GUI::Transcript -severity error -msg "Illegal seeting for -mirror switch, must be one of none, x, y, or xy."
                GUI::StatusBar::UpdateStatus -busy off
                return
            }

            ##  Set the target cell name based on the mirror switch
            switch -exact $V(-mirror) {
                x {
                    set target [format "%s-mirror-x" $device]
                }
                y {
                    set target [format "%s-mirror-y" $device]
                }
                xy {
                    set target [format "%s-mirror-xy" $device]
                }
                none -
                default {
                    set target $device
                }
            }

            GUI::StatusBar::UpdateStatus -busy on
            set ::ediu(sTime) [clock format [clock seconds] -format "%m/%d/%Y %T"]

            ##  Make sure a Target library or design has been defined

            if {$::ediu(targetPath) == $::ediu(Nothing) && $::ediu(connectMode) != True } {
                if {$GUI::Dashboard::Mode == $::ediu(designMode)} {
                    GUI::Transcript -severity error -msg "No Design (PCB) specified, build aborted."
                } elseif {$GUI::Dashboard::Mode == $::ediu(libraryMode)} {
                    GUI::Transcript -severity error -msg "No Central Library (LMC) specified, build aborted."
                } else {
                    puts $GUI::Dashboard::Mode
                    GUI::Transcript -severity error -msg "Mode not set, build aborted."
                }

                GUI::StatusBar::UpdateStatus -busy off
                return
            }

            ##  Invoke the Cell Editor and open the LMC or PCB
            ##  Catch any exceptions raised by opening the database

            set errorCode [catch { MGC::OpenCellEditor } errorMessage]
            if {$errorCode != 0} {
                GUI::Transcript -severity error -msg [format "API error \"%s\", build aborted." $errorMessage]
                MGC::CloseCellEditor
                GUI::StatusBar::UpdateStatus -busy off
                return
            }

            ##  Handling existing cells is much different for library
            ##  mode than it is for design mode.  In design mode there
            ##  isn't a "partition" so none of the partition logic applies.

            if { $GUI::Dashboard::Mode == $::ediu(libraryMode) } {

                #  Prompt for the Partition if not supplied with -partition

                if { [string equal $V(-partition) ""] } {
                    set ::ediu(cellEdtrPrtnName) \
                        [AIFForms::SelectOneFromList "Select Target Cell Partition" $::ediu(cellEdtrPrtnNames)]

                    if { [string equal $::ediu(cellEdtrPrtnName) ""] } {
                        GUI::Transcript -severity error -msg "No Cell Partition selected, build aborted."
                        MGC::CloseCellEditor
                        GUI::StatusBar::UpdateStatus -busy off
                        return
                    } else {
                        set ::ediu(cellEdtrPrtnName) [lindex $::ediu(cellEdtrPrtnName) 1]
                    }
                } else {
                    set ::ediu(cellEdtrPrtnName) $V(-partition)
                }

                #  Does the cell exist?  Before we can check, we need a
                #  partition.  There isn't a clear name as to what the
                #  partition name should be so we'll use the name of the
                #  cell as the name of the partition as well.

                #  Cannot access partition list when application is
                #  visible so if it is, hide it temporarily.
                set visibility $::ediu(appVisible)

                $::ediu(cellEdtr) Visible False
                set partitions [$::ediu(cellEdtrDb) Partitions]
                $::ediu(cellEdtr) Visible $visibility

                GUI::Transcript -severity note -msg [format "Found %s cell %s." [$partitions Count] \
                    [ediuPlural [$partitions Count] "partition"]]

                set pNames {}
                for {set i 1} {$i <= [$partitions Count]} {incr i} {
                    set partition [$partitions Item $i]
                    lappend pNames [$partition Name]
                }

                #  Does the partition exist?

                if { [lsearch $pNames $::ediu(cellEdtrPrtnName)] == -1 } {
                    GUI::Transcript -severity note -msg [format "Creating partition \"%s\" for cell \"%s\"." \
                        $::die(partition) $target]

                    set partition [$::ediu(cellEdtrDb) NewPartition $::ediu(cellEdtrPrtnName)]
                } else {
                    GUI::Transcript -severity note -msg [format "Using existing partition \"%s\" for cell \"%s\"." \
                        $::ediu(cellEdtrPrtnName) $target]
                    set partition [$partitions Item [expr [lsearch $pNames $::ediu(cellEdtrPrtnName)] +1]]
                }

                #  Now that the partition work is doene, does the cell exist?

                set cells [$partition Cells]
            } else {
                if { [expr { $V(-partition) ne "" }] } {
                    GUI::Transcript -severity warning -msg "-partition switch is ignored in Design Mode."
                }
                set partition [$::ediu(cellEdtrDb) ActivePartition]
                set cells [$partition Cells]
            }

            GUI::Transcript -severity note -msg [format "Found %s %s." [$cells Count] \
                [ediuPlural [$cells Count] "cell"]]

            set cNames {}
            for {set i 1} {$i <= [$cells Count]} {incr i} {
                set cell [$cells Item $i]
                lappend cNames [$cell Name]
            }

            #  Does the cell exist?  Are we using Name suffixes?

            if { [string equal $GUI::Dashboard::CellSuffix numeric] } {
                set suffixes [lsearch -all -inline -regexp  $cNames $target-\[0-9\]+]
                if { [string equal $suffixes ""] } {
                    set suffix "-1"
                } else {
                    ##  Get the suffix with the highest number
                    set suffix [string trim [string trimleft \
                        [lindex [lsort -increasing -integer $suffixes] end] $target] -]
                    incr suffix
                }
                ##  Add the suffix to the target
                append target $suffix
            } elseif { [string equal $GUI::Dashboard::CellSuffix alpha] } {
                ##  This is limited to 26 matches for now ...
                set suffixes [lsearch -all -inline -regexp  $cNames $target-\[A-Z\]+]
                if { [string equal $suffixes ""] } {
                    set suffix "-A"
                } else {
                    ##  Get the suffix with the highest letter
                    set suffix [string trim [string trimleft \
                        [lindex [lsort -increasing -ascii $suffixes] end] $target] -]

                    ##  Make sure the end of the alphabet hasn't been reached
                    if { [string equal $suffix Z] } {
                        GUI::Transcript -severity note -msg [format "Cell suffixes (\"%s\") exhausted, aborted." $suffix]
                        MGC::CloseCellEditor
                        return
                    }

                    ##  Increment the suffix
                    set suffix [format "-%c" [expr [scan $suffix %c] +1]]
                }
                ##  Add the suffix to the target
                append target $suffix
            } elseif { [string equal $GUI::Dashboard::CellSuffix datestamp] } {
                set suffix [clock format [clock seconds] -format {-%Y-%m-%d}]
                append target $suffix
            } elseif { [string equal $GUI::Dashboard::CellSuffix timestamp] } {
                set suffix [clock format [clock seconds] -format {-%Y-%m-%d-%H-%M-%S}]
                append target $suffix
            } else {
            }

            ##  If cell already exists, try and delete it.
            ##  This can fail if the cell is being referenced by the design.

            if { [lsearch $cNames $target] == -1 } {
                GUI::Transcript -severity note -msg [format "Creating new cell \"%s\"." $target]
            } else {
                GUI::Transcript -severity note -msg [format "Replacing existing cell \"%s.\"" $target]
                set cell [$cells Item [expr [lsearch $cNames $target] +1]]

                ##  Delete the cell and save the database.  The delete
                ##  isn't committed until the database is actually saved.

                set errorCode [catch { $cell Delete } errorMessage]
                if {$errorCode != 0} {
                    GUI::Transcript -severity error -msg [format "API error \"%s\", build aborted." $errorMessage]
                    MGC::CloseCellEditor
                    return
                }

                $::ediu(cellEdtr) SaveActiveDatabase
            }

            ##  Build a new cell.  The first part of this is done in
            ##  in the Cell Editor which is part of the Library Manager.
            ##  The graphics and pins are then added using the Cell Editor
            ##  AddIn which sort of looks like a mini version of Expedititon.

            set devicePinCount [llength $::devices($device)]

            set newCell [$partition NewCell [expr $::CellEditorAddinLib::ECellDBCellType(ecelldbCellTypePackage)]]

            $newCell -set Name $target
            $newCell -set Description $target
            $newCell -set MountType [expr $::CellEditorAddinLib::ECellDBMountType(ecelldbMountTypeSurface)]
            #$newCell -set LayerCount [expr 2]
            $newCell -set PinCount [expr $devicePinCount]
            #puts [format "--->  devicePinCount:  %s" $devicePinCount]
            $newCell -set Units [expr [MapEnum::Units $::database(units) "cell"]]

            ##  Set the package group to Bare Die unless this is the BGA device
            if { [string equal $::bga(name) $device] } {
                $newCell -set PackageGroup [expr $::CellEditorAddinLib::ECellDBPackageGroup(ecelldbPackageBGA)]
            } else {
                $newCell -set PackageGroup  [expr $::CellEditorAddinLib::ECellDBPackageGroup(ecelldbPackageBareDie)]
            }

            ##  Commit the cell to the database so it can
            ##  be edited using the Cell Editor AddIn.

            $newCell Commit

            ##  Put the Cell in "Graphical Edit" mode
            ##  to add the pins and graphics.

            ##  Invoke the Padstack Editor and open the target
            ##  Catch any exceptions raised by opening the database
            set errorCode [catch { MGC::OpenPadstackEditor -dontopendatabase } errorMessage]
            if {$errorCode != 0} {
                GUI::Transcript -severity error -msg [format "API error \"%s\", build aborted." $errorMessage]
                GUI::StatusBar::UpdateStatus -busy off
                return
            }

            ##  Open the Cell Editor and turn off prompting

            set cellEditor [$newCell Edit]
            set cellEditorDoc [$cellEditor Application]
            [$cellEditorDoc Gui] SuppressTrivialDialogs True


            ##  Need the Component Document to it can be edited.
            ##  When using the Cell Editor Addin, the component will
            ##  always be the first Item.

            set components [$cellEditor Components]
            set component [$components Item 1]

            ##  Add the pins

            #  Doe the pads exist?

            set pads [Netlist::GetPads]

            foreach pad $pads {
                set padstack($pad) [$::ediu(pdstkEdtrDb) FindPadstack $pad]

                #  Echo some information about what will happen.

                if {$padstack($pad) == $::ediu(Nothing)} {
                    GUI::Transcript -severity error -msg \
                        [format "Reference Padstack \"%s\" does not exist, build aborted." $pad]
                    $cellEditor Close False

                    if { $GUI::Dashboard::Mode == $::ediu(designMode) } {
                        MGC::ClosePadstackEditor -dontclosedatabase
                    } else {
                        MGC::ClosePadstackEditor
                    }
                    MGC::CloseCellEditor

                    GUI::StatusBar::UpdateStatus -busy off
                    return -1
                }
            }

            ##  To fix Tcom bug?
            if { $GUI::Dashboard::Mode == $::ediu(designMode) } {
                MGC::ClosePadstackEditor -dontclosedatabase
            } else {
                MGC::ClosePadstackEditor
            }

            ##  Need to "Put" the padstack so it can be
            ##  referenced by the Cell Editor Add Pin process.

            #foreach pad $pads {
            #    set padstack($pad) [$cellEditor PutPadstack [expr 1] [expr 1] $pad]
            #}

            set i 0
            unset padstack

            set pins [$cellEditor Pins]
            #puts [format "-->  Array Size of pins:  %s" [$pins Count]]

            ##  Start Transations for performance reasons
            $cellEditor TransactionStart [expr $::MGCPCB::EPcbDRCMode(epcbDRCModeDRC)]

            ##  Loop over the collection of pins
            ::tcom::foreach pin $pins {
                ##  Split of the fields extracted from the die file

                set padDefinition [lindex $::devices($device) $i]

                set diePadFields(padname) [lindex $padDefinition 0]
                set diePadFields(pinnum) [lindex $padDefinition 1]

                switch -exact $V(-mirror) {
                    x {
                        set diePadFields(padx) [expr - [lindex $padDefinition 2]]
                        set diePadFields(pady) [lindex $padDefinition 3]
                    }
                    y {
                        set diePadFields(padx) [lindex $padDefinition 2]
                        set diePadFields(pady) [expr - [lindex $padDefinition 3]]
                    }
                    xy {
                        set diePadFields(padx) [expr - [lindex $padDefinition 2]]
                        set diePadFields(pady) [expr - [lindex $padDefinition 3]]
                    }
                    none -
                    default {
                        set diePadFields(padx) [lindex $padDefinition 2]
                        set diePadFields(pady) [lindex $padDefinition 3]
                    }
                }
                #set diePadFields(net) [Netlist::GetNetName $i]

                #printArray diePadFields

                ## Need to handle sparse mode?

                set skip False

        if { 0 } {
                if { $::ediu(sparseMode) } {
                    if { [lsearch $::ediu(sparsepinnames) $diePadFields(pinnum)] == -1 } {
                        set skip True
                    }
                }
        }

                if { $skip  == False } {
                    GUI::Transcript -severity note -msg [format "Placing pin \"%s\" using padstack \"%s\"." \
                        $diePadFields(pinnum) $diePadFields(padname)]

                    ##  Need to "Put" the padstack so it can be
                    ##  referenced by the Cell Editor Add Pin process.

                    set padstack [$cellEditor PutPadstack [expr 1] [expr 1] $diePadFields(padname)]

                    $pin CurrentPadstack $padstack
                    $pin SetName $diePadFields(pinnum)

                    set errorCode [catch { $pin Place \
                        [expr $diePadFields(padx)] [expr $diePadFields(pady)] [expr 0] } errorMessage]
                    if {$errorCode != 0} {
                        GUI::Transcript -severity error -msg [format "API error \"%s\", build aborted." $errorMessage]
                        #puts [format "Error:  %s  Pin:  %d  Handle:  %s" $errorMessage $i $pin]

                        #puts [$pin IsValid]
                        #puts [$pin Name]
                        #puts [format "-->  Array Size of pins:  %s" [$pins Count]]
                        #puts [$cellEditor Name]
                        break
                    }
                } else {
                    GUI::Transcript -severity note -msg [format "Skipping pin \"%s\" using padstack \"%s\", not in Sparse Pin list." \
                        $diePadFields(pinnum) $diePadFields(padname)]
                }

                set pin ::tcom::null

                incr i
            }

            ## Define the placement outline

            if { $::ediu(MCMAIF) == 1 } {
                ##  Device might be the BGA ... need to account
                ##  for that possibility before trying to extract
                ##  the height and width from a non-existant section

                foreach i [dict keys $::mcmdie] {
                    if { [string equal [dict get $::mcmdie $i] $device] } {
                        set section [format "MCM_%s_%s" [dict get $::mcmdie $i] $i]
                        puts "-->  Section:  $section"
                    }
                }

                if { [lsearch [AIF::Sections] $section] == -1 } {
                    set width [AIF::GetVar WIDTH BGA]
                    set height [AIF::GetVar HEIGHT BGA]
                } else {
                    set width [AIF::GetVar WIDTH $section]
                    set height [AIF::GetVar HEIGHT $section]
                }
            } else {
                set width [AIF::GetVar WIDTH DIE]
                set height [AIF::GetVar HEIGHT DIE]
            }

            set x2 [expr $width / 2]
            set x1 [expr -1 * $x2]
            set y2 [expr $height / 2]
            set y1 [expr -1 * $y2]

            ##  PutPlacementOutline expects a Points Array which isn't easily
            ##  passed via Tcl.  Use the Utility object to create a Points Array
            ##  Object Rectangle.  A rectangle will have 5 points in the points
            ##  array - 5 is passed as the number of points to PutPlacemetOutline.

            set ptsArray [[$cellEditorDoc Utility] CreateRectXYR $x1 $y1 $x2 $y2]

            ##  Need some sort of a thickness value - there isn't one in the AIF file
            ##  We'll assume 50 microns for now, may offer user ability to define later.

            set th [[$cellEditorDoc Utility] ConvertUnit [expr 50.0] \
                [expr $::CellEditorAddinLib::ECellDBUnit(ecelldbUnitUM)] \
                [expr [MapEnum::Units $::database(units) "cell"]]]

            ##  Add the Placment Outline
            $cellEditor PutPlacementOutline [expr $::MGCPCB::EPcbSide(epcbSideMount)] 5 $ptsArray \
                [expr $th] [expr 0] $component [expr [MapEnum::Units $::database(units) "cell"]]

            ##  Terminate transactions
            $cellEditor TransactionEnd True

            ##  Save edits and close the Cell Editor
            set time [clock format [clock seconds] -format "%m/%d/%Y %T"]
            GUI::Transcript -severity note -msg [format "Saving new cell \"%s\" (%s)." $target $time]
            $cellEditor Save
            set time [clock format [clock seconds] -format "%m/%d/%Y %T"]
            GUI::Transcript -severity note -msg [format "New cell \"%s\" (%s) saved." $target $time]
            $cellEditor Close False

        ##    if { $GUI::Dashboard::Mode == $::ediu(designMode) } {
        ##        MGC::ClosePadstackEditor -dontclosedatabase
        ##    } else {
        ##        MGC::ClosePadstackEditor
        ##    }
            MGC::CloseCellEditor

            ##  Report some time statistics
            set ::ediu(cTime) [clock format [clock seconds] -format "%m/%d/%Y %T"]
            GUI::Transcript -severity note -msg [format "Start Time:  %s" $::ediu(sTime)]
            GUI::Transcript -severity note -msg [format "Completion Time:  %s" $::ediu(cTime)]

            GUI::StatusBar::UpdateStatus -busy off
        }

        #
        #  MGC::Generate::PDB
        #
        proc PDB { device args } {
            ##  Process command arguments
            array set V [list {-partition} $GUI::Dashboard::PartPartition] ;# Default values
            foreach {a value} $args {
                if {! [info exists V($a)]} {error "unknown option $a"}
                if {$value == {}} {error "value of \"$a\" missing"}
                set V($a) $value
            }

            set ::ediu(partEdtrPrtnName) $V(-partition)

            GUI::StatusBar::UpdateStatus -busy on
            set ::ediu(sTime) [clock format [clock seconds] -format "%m/%d/%Y %T"]

            ##  Make sure a Target library or design has been defined

            if {$::ediu(targetPath) == $::ediu(Nothing) && $::ediu(connectMode) != True } {
                if {$GUI::Dashboard::Mode == $::ediu(designMode)} {
                    GUI::Transcript -severity error -msg "No Design (PCB) specified, build aborted."
                } elseif {$GUI::Dashboard::Mode == $::ediu(libraryMode)} {
                    GUI::Transcript -severity error -msg "No Central Library (LMC) specified, build aborted."
                } else {
                    GUI::Transcript -severity error -msg "Mode not set, build aborted."
                }

                GUI::StatusBar::UpdateStatus -busy off
                return
            }

            ##  Invoke the PDB Editor and open the database
            ##  Catch any exceptions raised by opening the database

            set errorCode [catch { MGC::OpenPDBEditor } errorMessage]
            if {$errorCode != 0} {
                GUI::Transcript -severity error -msg [format "API error \"%s\", build aborted." $errorMessage]
                GUI::StatusBar::UpdateStatus -busy off
                return
            }

            ##  Handling existing parts is much different for library
            ##  mode than it is for design mode.  In design mode there
            ##  isn't a "partition" so none of the partition logic applies.

            if { $GUI::Dashboard::Mode == $::ediu(libraryMode) } {
                #  Does the part exist?  Before we can check, we need a
                #  partition.  There isn't a clear name as to what the
                #  partition name should be so we'll use the name of the
                #  part as the name of the partition as well.

                #  Prompt for the Partition if not supplied with -partition

                if { [string equal $V(-partition) ""] } {
                    set ::ediu(partEdtrPrtnName) \
                        [AIFForms::SelectOneFromList "Select Target Part Partition" $::ediu(partEdtrPrtnNames)]

                    if { [string equal $::ediu(partEdtrPrtnName) ""] } {
                        GUI::Transcript -severity error -msg "No Part Partition selected, build aborted."
                        MGC::CloseCellEditor
                        GUI::StatusBar::UpdateStatus -busy off
                        return
                    } else {
                        set ::ediu(partEdtrPrtnName) [lindex $::ediu(partEdtrPrtnName) 1]
                    }
                } else {
                    set ::ediu(partEdtrPrtnName) $V(-partition)
                }


                set partitions [$::ediu(partEdtrDb) Partitions]

                GUI::Transcript -severity note -msg [format "Found %s part %s." [$partitions Count] \
                    [ediuPlural [$partitions Count] "partition"]]

                set pNames {}
                for {set i 1} {$i <= [$partitions Count]} {incr i} {
                    set partition [$partitions Item $i]
                    lappend pNames [$partition Name]
                }

                #  Does the partition exist?

                if { [lsearch $pNames $::ediu(partEdtrPrtnName)] == -1 } {
                    GUI::Transcript -severity note -msg [format "Creating partition \"%s\" for part \"%s\"." \
                        $::ediu(partEdtrPrtnName) $device]

                    set partition [$::ediu(partEdtrDb) NewPartition $::ediu(partEdtrPrtnName)]
                } else {
                    GUI::Transcript -severity note -msg [format "Using existing partition \"%s\" for part \"%s\"." \
                        $::ediu(partEdtrPrtnName) $device]
                    set partition [$partitions Item [expr [lsearch $pNames $::ediu(partEdtrPrtnName)] +1]]
                }

                #  Now that the partition work is doene, does the part exist?

                set parts [$partition Parts]
            } else {
                if { [expr { $V(-partition) ne "" }] } {
                    GUI::Transcript -severity warning -msg "-partition switch is ignored in Design Mode."
                }
                set partition [$::ediu(partEdtrDb) ActivePartition]
                set parts [$partition Parts]
            }

            GUI::Transcript -severity note -msg [format "Found %s %s." [$parts Count] \
                [ediuPlural [$parts Count] "part"]]

            set cNames {}
            for {set i 1} {$i <= [$parts Count]} {incr i} {
                set part [$parts Item $i]
                lappend cNames [$part Name]
            }

            #  Does the part exist?

            if { [lsearch $cNames $device] == -1 } {
                GUI::Transcript -severity note -msg [format "Creating new part \"%s\"." $device]

            } else {
                GUI::Transcript -severity note -msg [format "Replacing existing part \"%s.\"" $device]
                set part [$parts Item [expr [lsearch $cNames $device] +1]]

                ##  Delete the part and save the database.  The delete
                ##  isn't committed until the database is actually saved.

                ##  First delete the Symbol Reference

                set errorCode [catch { $part Delete } errorMessage]
                if {$errorCode != 0} {
                    GUI::Transcript -severity error -msg [format "API error \"%s\", build aborted." $errorMessage]
                    MGC::ClosePDBEditor
                    GUI::StatusBar::UpdateStatus -busy off
                    return
                }
            }

            $::ediu(partEdtr) SaveActiveDatabase

            ##  Generate a new part.  The first part of this is done in
            ##  in the PDB Editor which is part of the Library Manager.
            ##  The graphics and pins are then added using the PDB Editor
            ##  AddIn which sort of looks like a mini version of Expediiton.

            set newPart [$partition NewPart]

            $newPart -set Name $device
            $newPart -set Number $device
            $newPart -set Type [expr $::MGCPCBPartsEditor::EPDBPartType(epdbPartIC)]
            $newPart -set RefDesPrefix "U"
            $newPart -set Description "IC"

            #  Commit the Part so it can be mapped.
            $newPart Commit

            #  Start doing the pin mapping
            set mapping [$newPart PinMapping]

            #  Does the part have any symbol references?
            #  Need to remove existing reference before adding a symbol reference
            set symRef [$mapping PutSymbolReference $device]

            if { [[$mapping SymbolReferences] Count] > 0 } {
                GUI::Transcript -severity warning -msg \
                    [format "Mapping has %d preexisting Symbol Reference(s)." \
                        [[$mapping SymbolReferences] Count]]

                for { set i 1 } {$i <= [[$mapping SymbolReferences] Count] } {incr i} {
                    GUI::Transcript -severity note -msg \
                        [format "Removing prexisting symbol reference #%d" $i]
                    [$mapping SymbolReferences] Remove $i
                }
            }

            #  Need to add a cell reference
            set cellRef [$mapping PutCellReference $device \
                $::MGCPCBPartsEditor::EPDBCellReferenceType(epdbCellRefTop) $device]

            set devicePinCount [llength $::devices($device)]

            ##  Define the gate - what to do about swap code?
            set gate [$mapping PutGate "gate_1" $devicePinCount \
                $::MGCPCBPartsEditor::EPDBGateType(epdbGateTypeLogical)]

            ##  Add a pin defintition for each pin to the gate
            ##  The swap code for all of the pins is set to "1"
            ##  which ensures the pins are swappable within Expedition.

            set pi 1
            foreach p $::devices($device) {
                set sc [lindex $p 1]
                GUI::Transcript -severity note -msg [format "Adding Pin Definition %d \"%s\" %d \"Unknown\"" \
                    $pi $sc [expr $::MGCPCBPartsEditor::EPDBPinPropertyType(epdbPinPropertyPinType)]]
                $gate PutPinDefinition [expr $pi] "1" \
                    [expr $::MGCPCBPartsEditor::EPDBPinPropertyType(epdbPinPropertyPinType)] "Unknown"
                incr pi
            }

            ##  Report symbol reference count.  Not sure this is needed ...

            if { [[$mapping SymbolReferences] Count] != 0 } {
                GUI::Transcript -severity warning -msg \
                    [format "Symbol Reference \"%s\" is already defined." $device]

                #set i 1
                #set pinNames [$symRef PinNames]
                #puts "----------->$pinNames"
                #foreach pn $pinNames {
                    #puts "2-$i -->  Symbol Pin Name:  $pn"
                    #incr i
                #}
            }

            ##  Define the slot
            set slot [$mapping PutSlot $gate $symRef]

            ##  Add a pin defintition for each pin to the slot
            set pi 1
            foreach p $::devices($device) {
                ##  Get the pin name
                set sc [lindex $p 1]


                ## Need to handle sparse mode?
                if { $::ediu(sparseMode) } {
                    #if { $i in ::ediu(sparsepinnumbers) $i } {
                    #    $slot PutPin [expr $i] [format "%s" $i]
                    #}
                } else {
                    GUI::Transcript -severity note -msg [format "Adding pin %d (\"%s\") to slot." $pi $sc]
                    $slot PutPin [expr $pi] [format "%s" $sc] [format "%s" $pi]
                }
                incr pi
            }

            ##  Commit mapping and close the PDB editor

            GUI::Transcript -severity note -msg [format "Saving PDB \"%s\"." $device]
            $mapping Commit
            GUI::Transcript -severity note -msg [format "New PDB \"%s\" saved." $device]
            MGC::ClosePDBEditor

            ##  Report some time statistics
            set ::ediu(cTime) [clock format [clock seconds] -format "%m/%d/%Y %T"]
            GUI::Transcript -severity note -msg [format "Start Time:  %s" $::ediu(sTime)]
            GUI::Transcript -severity note -msg [format "Completion Time:  %s" $::ediu(cTime)]
            GUI::StatusBar::UpdateStatus -busy off
        }

        #
        #  MGC::Generate::Pads
        #
        #  This subroutine will create die pads based on the "PADS" section
        #  found in the AIF file.  It can optionally replace an existing pad
        #  based on the second argument.
        #

        proc Pads { } {
            foreach i [AIFForms::SelectFromList "Select Pad(s)" [AIF::Pad::GetAllPads]] {
                set p [lindex $i 1]
                set ::padGeom(name) $p
                set ::padGeom(shape) [AIF::Pad::GetShape $p]
                set ::padGeom(width) [AIF::Pad::GetWidth $p]
                set ::padGeom(height) [AIF::Pad::GetHeight $p]
                set ::padGeom(offsetx) 0.0
                set ::padGeom(offsety) 0.0

                MGC::Generate::Pad
            }
        }

        #
        #  MGC::GenerateMGC::Padstacks
        #
        #  This subroutine will create die pads based on the "PADS" section
        #  found in the AIF file.  It can optionally replace an existing pad
        #  based on the second argument.
        #

        proc Padstacks { } {
            foreach i [AIFForms::SelectFromList "Select Pad(s)" [AIF::Pad::GetAllPads]] {
                set p [lindex $i 1]
                set ::padGeom(name) $p
                set ::padGeom(shape) [AIF::Pad::GetShape $p]
                set ::padGeom(width) [AIF::Pad::GetWidth $p]
                set ::padGeom(height) [AIF::Pad::GetHeight $p]
                set ::padGeom(offsetx) 0.0
                set ::padGeom(offsety) 0.0

                MGC::Generate::Padstack
            }
        }

        #
        #  MGC::Generate::Cells
        #
        #  This subroutine will create die pads based on the "PADS" section
        #  found in the AIF file.  It can optionally replace an existing pad
        #  based on the second argument.
        #

        proc Cells { } {
            foreach i [AIFForms::SelectFromList "Select Cell(s)" [array names ::devices]] {
                foreach j [array names GUI::Dashboard::CellGeneration] {
                    if { [string is true $GUI::Dashboard::CellGeneration($j)] } {
                        MGC::Generate::Cell [lindex $i 1] -mirror [string tolower [string trimleft $j Mirror]]
                    }
                }
            }
        }

        #
        #  MGC::Generate::PDBs
        #
        #  This subroutine will create die pads based on the "PADS" section
        #  found in the AIF file.  It can optionally replace an existing pad
        #  based on the second argument.
        #

        proc PDBs { } {
            foreach i [AIFForms::SelectFromList "Select PDB(s)" [array names ::devices]] {
                MGC::Generate::PDB [lindex $i 1]
            }
        }
    }

    ##
    ##  Define the Bond Wire namespace and procedures supporting bond wire and pad operations
    ##
    ##  These parameters, provided by Frank Bader, are fairly generic and general purpose.
    ##
    namespace eval WireBond {

        variable WBParameters
        variable WBDRCProperty
        variable WBRule
        variable Units um
        variable Angle deg

        array set WBParameters {
            Model DefaultWireModel
            Padstack ""
            XStart 0
            YStart 0
            XEnd 0
            YEnd 0
        }

        array set WBDRCProperty {
            WB2WB 0
            WB2Part 4
            WB2Metal 0
            WB2DieEdge 4
            WB2DieSurface 0
            WB2Cavity 0
            WBAngle 360
            BondSiteMargin 0
            WBMin 100
            WBMax 3000
        }

        array set WBRule {
            Name DefaultWireModel
            BWW 25
            Template {[Name=[DefaultWireModel]][IsMod=[No]][Cs=[[[X=[0]][Y=[0]][Z=[(BWH)]][R=[0]][CT=[Ball]]][[X=[0]][Y=[0]][Z=[(BWH)*1.5]][R=[100um]][CT=[Round]]][[X=[(BWD)/3*2]][Y=[0]][Z=[(BWH)*1.5]][R=[200um]][CT=[Round]]][[X=[(BWD)]][Y=[0]][Z=[(IH)]][R=[0]][CT=[Wedge]]]]][Vs=[[BD=[BWW+15um]][BH=[15um]][BWD=[3000um]][BWH=[300um]][BWW=[%s%s]][IH=[30um]][WL=[30um]]]]}
            Value ""
        }

        set WBRule(Value) [format $WBRule(Template) $WBRule(BWW) $Units]

        ##
        ##  MGC::WireBond::UpdateParameters
        ##
        proc UpdateParameters {} {
            variable Units
            variable WBParameters
            set GUI::Dashboard::WBParameters [format \
                {[Model=[%s]][Padstack=[%s]][XStart=[%s%s]][YStart=[%s%s]][XEnd=[%s%s]][YEnd=[%s%s]]} \
                $WBParameters(Model) $WBParameters(Padstack) \
                $WBParameters(XStart) $Units $WBParameters(YStart) $Units \
                $WBParameters(XEnd) $Units $WBParameters(YEnd) $Units]
        }

        ##
        ##  MGC::WireBond::UpdateDRCProperty
        ##
        proc UpdateDRCProperty {} {
            variable Angle
            variable Units
            variable WBDRCProperty
            set GUI::Dashboard::WBDRCProperty [format \
                {[WB2WB=[%s%s]][WB2Part=[%s%s]][WB2Metal=[%s%s]][WB2DieEdge=[%s%s]][WB2DieSurface=[%s%s]][WB2Cavity=[%s%s]][WBAngle=[%s%s]][BondSiteMargin=[%s%s]][Rows=[[[WBMin=[%s%s]][WBMax=[%s%s]]]]]} \
                    $WBDRCProperty(WB2WB) $Units $WBDRCProperty(WB2Part) $Units $WBDRCProperty(WB2Metal) $Units \
                    $WBDRCProperty(WB2DieEdge) $Units $WBDRCProperty(WB2DieSurface) $Units $WBDRCProperty(WB2Cavity) $Units \
                    $WBDRCProperty(WBAngle) $Angle $WBDRCProperty(BondSiteMargin) $Units $WBDRCProperty(WBMin) $Units \
                    $WBDRCProperty(WBMax) $Units]
        }

        ##
        ##  MGC::WireBond::SelectBondPad
        ##
        proc SelectBondPad {} {
            set bondpads [list]

            foreach i [dict keys $::padtypes] {
                set type [dict get $::padtypes $i]

                if { [string equal bondpad $type] } {
                    lappend bondpads $i
                }
            }

            set MGC::WireBond::WBParameters(Padstack) \
                [AIFForms::SelectOneFromList "Select Bond Pad" $bondpads]
            if { [string equal $MGC::WireBond::WBParameters(Padstack) ""] } {
                GUI::Transcript -severity error -msg "No bond pad selected."
                return
            } else {
                set MGC::WireBond::WBParameters(Padstack) [lindex $MGC::WireBond::WBParameters(Padstack) 1]
            }
        }

        ##
        ##  MGC::WireBond::Setup
        ##
        proc Setup {} {
            variable WBParameters
            printArray WBParameters
            puts "MGC::WireBond::Setup"
            $GUI::widgets(notebook) select $GUI::widgets(wirebondparams)
        }

        ##
        ##  MGC::WireBond::ApplyProperies
        ##
        proc ApplyProperies {} {
            puts "MGC::WireBond::ApplyProperies"
            ##  Which mode?  Design or Library?
            if { $GUI::Dashboard::Mode == $::ediu(designMode) } {
                ##  Invoke Expedition on the design so the Cell Editor can be started
                ##  Catch any exceptions raised by opening the database
                set errorCode [catch { MGC::OpenExpedition } errorMessage]
                if {$errorCode != 0} {
                    GUI::Transcript -severity error -msg [format "API error \"%s\", build aborted." $errorMessage]
                    GUI::StatusBar::UpdateStatus -busy off
                    return
                }
                set ::ediu(cellEdtr) [$::ediu(pcbDoc) CellEditor]
            } else {
                GUI::Transcript -severity error -msg "Bond Pad placement is only available in design mode."
                return
            }

            ##  Check the property values and make sure they are set.
            if { [string equal $GUI::Dashboard::WBParameters ""] } {
                GUI::Transcript -severity error -msg "Wire Bond Parameters property has not been set."
                return
            }

            if { [string equal $GUI::Dashboard::WBDRCProperty ""] } {
                GUI::Transcript -severity error -msg "Wire Bond DRC property has not been set."
                return
            }

            ##  Apply the properties to the PCB Doc
            $::ediu(pcbDoc) PutProperty "WBParameters" $GUI::Dashboard::WBParameters
            GUI::Transcript -severity note -msg "Wire Bond property \"WBParameters\" applied to design."
            $::ediu(pcbDoc) PutProperty "WBDRCProperty" $GUI::Dashboard::WBDRCProperty
            GUI::Transcript -severity note -msg "Wire Bond property \"WBDRCProperty\" applied to design."

            ##  Apply default wire model to all components
            set comps [$::ediu(pcbDoc) Components]
            ::tcom::foreach comp $comps {
                $comp PutProperty "WBParameters" {[Model=[DefaultWireModel]][PADS=[]]}
                GUI::Transcript -severity note -msg [format "Wire Bond property \"WBParameters\" applied to component \"%s\"." [$comp RefDes]]
            }
        }

        ##
        ##  MGC::WireBond::PlaceBondPads
        ##
        proc PlaceBondPads {} {
            puts "MGC::WireBond::PlaceBondPads"

            ##  Which mode?  Design or Library?
            if { $GUI::Dashboard::Mode == $::ediu(designMode) } {
                ##  Invoke Expedition on the design so the Cell Editor can be started
                ##  Catch any exceptions raised by opening the database
                set errorCode [catch { MGC::OpenExpedition } errorMessage]
                if {$errorCode != 0} {
                    GUI::Transcript -severity error -msg [format "API error \"%s\", build aborted." $errorMessage]
                    GUI::StatusBar::UpdateStatus -busy off
                    return
                }
            } else {
                GUI::Transcript -severity error -msg "Bond Pad placement is only available in design mode."
                return
            }

            ##  Start a transaction with DRC to get Bond Pads placed ...
            $::ediu(pcbDoc) TransactionStart [expr $::MGCPCB::EPcbDRCMode(epcbDRCModeNone)]
            
            foreach i $::bondpads {

                set bondpad(NETNAME) [lindex $i 0]
                set bondpad(FINNAME) [lindex $i 1]
                set bondpad(FIN_X) [lindex $i 2]
                set bondpad(FIN_Y) [lindex $i 3]
                set bondpad(ANGLE) [lindex $i 4]

                ##  Need to find the padstack ...
                ##  Make sure the Bond Pad exists and is defined as a Bond Pad
                set padstacks [$::ediu(pcbDoc) PadstackNames \
                    [expr $::MGCPCB::EPcbPadstackObjectType(epcbPadstackObjectBondPad)]]

                if { [lsearch $padstacks $bondpad(FINNAME)] == -1} {
                    GUI::Transcript -severity error -msg [format \
                        "Bond Pad \"%s\" does not appear in the design or is not defined as a Bond Pad." \
                        $bondpad(FINNAME)]
                    $::ediu(pcbDoc) TransactionEnd True
                    return
                } else {
                    GUI::Transcript -severity note -msg [format \
                    "Bond Pad \"%s\" found in design, will be placed." $bondpad(FINNAME)]
                }

                ##  Activate the Bond Pad padstack
                set padstack [$::ediu(pcbDoc) \
                    PutPadstack [expr 1] [expr 1] $bondpad(FINNAME)]

                set net [$::ediu(pcbDoc) FindNet $bondpad(NETNAME)]

                if { [string equal $net ""] } {
                    GUI::Transcript -severity warning -msg [format "Net \"%s\" was not found, may be a No Connect, using \"(Net0)\" as net." $bondpad(NETNAME)]
                    set net [$::ediu(pcbDoc) FindNet "(Net0)"]
                } else {
                    GUI::Transcript -severity note -msg [format "Net \"%s\" was found." $bondpad(NETNAME)]
                }

                ##  Place the Bond Pad
                GUI::Transcript -severity note -msg \
                    [format "Placing Bond Pad \"%s\" for Net \"%s\" (X: %s  Y: %s  R: %s)." \
                    $bondpad(FINNAME) $bondpad(NETNAME) $bondpad(FIN_X) $bondpad(FIN_Y) $bondpad(ANGLE)]
                set bpo [$::ediu(pcbDoc) PutBondPad \
                    [expr $bondpad(FIN_X)] [expr $bondpad(FIN_Y)] $padstack $net]
                $bpo -set Orientation \
                    [expr $::MGCPCB::EPcbAngleUnit(epcbAngleUnitDegrees)] [expr $bondpad(ANGLE)]

                puts [format "---------->  %s" [$bpo Name]]
                puts [format "Orientation:  %s" [$bpo -get Orientation]]
            }
            $::ediu(pcbDoc) TransactionEnd True
        }

        ##
        ##  MGC::BondWire::PlaceBondWires
        ##
        proc PlaceBondWires {} {
            puts "MGC::WireBond::PlaceBondWires"

            ##  Which mode?  Design or Library?
            if { $GUI::Dashboard::Mode == $::ediu(designMode) } {
                ##  Invoke Expedition on the design so the Cell Editor can be started
                ##  Catch any exceptions raised by opening the database
                set errorCode [catch { MGC::OpenExpedition } errorMessage]
                if {$errorCode != 0} {
                    GUI::Transcript -severity error -msg [format "API error \"%s\", build aborted." $errorMessage]
                    GUI::StatusBar::UpdateStatus -busy off
                    return
                }
            } else {
                GUI::Transcript -severity error -msg "Bond Pad placement is only available in design mode."
                return
            }

            GUI::StatusBar::UpdateStatus -busy on

            ##  Start a transaction with DRC to get Bond Pads placed ...
            $::ediu(pcbDoc) TransactionStart [expr $::MGCPCB::EPcbDRCMode(epcbDRCModeNone)]

            ##  Place each bond wire based on From XY and To XY
            foreach i $::bondwires {
                set bondwire(NETNAME) [lindex $i 0]
                set bondwire(FROM_X) [lindex $i 1]
                set bondwire(FROM_Y) [lindex $i 2]
                set bondwire(TO_X) [lindex $i 3]
                set bondwire(TO_Y) [lindex $i 4]

                ##  Try and "pick" the "FROM" Die Pin at the XY location.
                $::ediu(pcbDoc) UnSelectAll
                #puts "Picking FROM at X:  $bondwire(FROM_X)  Y:  $bondwire(FROM_Y)"
                set objs [$::ediu(pcbDoc) Pick \
                    [expr double($bondwire(FROM_X))] [expr double($bondwire(FROM_Y))] \
                    [expr double($bondwire(FROM_X))] [expr double($bondwire(FROM_Y))] \
                    [expr $::MGCPCB::EPcbObjectClassType(epcbObjectClassPadstackObject)] \
                    [$::ediu(pcbDoc) LayerStack]]

                ##  Making sure exactly "one" object was picked isn't possible - too many
                ##  things can be stacked on top of one another on different layers.  Need
                ##  to iterate through the selected objects and identify the Die Pin we're
                ##  actually looking for.

                set dpFound False

                if { [$objs Count] > 0 } {
                    ::tcom::foreach obj $objs {
                        set diepin [$obj CurrentPadstack]
                        if { [$diepin PinClass] == [expr $::MGCPCB::EPcbPinClassType(epcbPinClassDie)] } {
                            set dpFound True
                            set DiePin [[$diepin Pins] Item 1]
                            break
                        }
                    }
                }

                if { [string is false $dpFound] } {
                    GUI::Transcript -severity error -msg \
                        [format "Unable to pick die pad at bond wire origin (X: %f  Y: %f), bond wire skipped (Net: %s  From (%f, %f) To (%f, %f)." \
                        $bondwire(FROM_X) $bondwire(FROM_Y) $bondwire(NETNAME) \
                        $bondwire(FROM_X) $bondwire(FROM_Y) $bondwire(TO_X) $bondwire(TO_Y)]
$::ediu(pcbDoc) TransactionEnd True
break
                        continue
                } else {
                    GUI::Transcript -severity note -msg \
                        [format "Found Die Pin at bond wire origin (X: %f  Y: %f) for net \"%s\"." \
                            $bondwire(FROM_X) $bondwire(FROM_Y) $bondwire(NETNAME)]
                }

                ##  Validated it is correct type, now need just the object selected
                ## Need to select the Pin Object as PutBondWire requires a Pin Object
                #$DiePin Selected True

                ##  Try and "pick" the "TO" Bond Pad at the XY location.

                $::ediu(pcbDoc) UnSelectAll

                #puts "Picking TO at X:  $bondwire(TO_X)  Y:  $bondwire(TO_Y)"
                set objs [$::ediu(pcbDoc) Pick \
                    [expr double($bondwire(TO_X))] [expr double($bondwire(TO_Y))] \
                    [expr double($bondwire(TO_X))] [expr double($bondwire(TO_Y))] \
                    [expr $::MGCPCB::EPcbObjectClassType(epcbObjectClassPadstackObject)] \
                    [$::ediu(pcbDoc) LayerStack]]

                ##  Making sure exactly "one" object was picked isn't possible - too many
                ##  things can be stacked on top of one another on different layers.  Need
                ##  to iterate through the selected objects and identify the Bond Pad we're
                ##  actually looking for.

                set bpFound False

                if { [$objs Count] > 0 } {
                    ::tcom::foreach obj $objs {
                        set bondpad [$obj CurrentPadstack]
                        if {([$bondpad PinClass] == [expr $::MGCPCB::EPcbPinClassType(epcbPinClassSMD)]) && \
                            ([$bondpad Type] == [expr $::MGCPCB::EPcbPadstackObjectType(epcbPadstackObjectBondPad)])} {
                            set bpFound True
                            set BondPad $obj
                            break
                        }
                    }
                }

                if { [string is false $bpFound] } {
                    GUI::Transcript -severity error -msg \
                        [format "Unable to pick bond pad at bond wire termination (X: %f  Y: %f), bond wire skipped (Net: %s  From (%f, %f) To (%f, %f)." \
                        $bondwire(TO_X) $bondwire(TO_Y) $bondwire(NETNAME) \
                        $bondwire(FROM_X) $bondwire(FROM_Y) $bondwire(TO_X) $bondwire(TO_Y)]
                        continue
                } else {
                    GUI::Transcript -severity note -msg \
                        [format "Found Bond Pad at bond wire termination (X: %f  Y: %f) for net \"%s\"." \
                            $bondwire(FROM_X) $bondwire(FROM_Y) $bondwire(NETNAME)]
                }

                ##  Validated it is correct type, now need just the object selected
                $BondPad Selected True

                ##  A die pin and bond pad pair have been identified, time to drop a bond wire
                set dpX [$DiePin PositionX]
                set dpY [$DiePin PositionY]
                set bpX [$BondPad PositionX]
                set bpY [$BondPad PositionY]

                set bw [$::ediu(pcbDoc) PutBondWire $DiePin $dpX $dpY $BondPad $bpX $bpY]
                GUI::Transcript -severity note -msg [format "Bond Wire successfully placed for net \"%s\" from (%f,%f) to (%f,%f)." \
                    $bondwire(NETNAME) $bondwire(FROM_X) $bondwire(FROM_Y) $bondwire(TO_X) $bondwire(TO_Y)]

                ##  Assign the BondWire model to ensure propert behavior
                
                GUI::Transcript -severity note -msg [format "Bond Wire Model \"%s\" assigned to net \"%s\"." \
                    $MGC::WireBond::WBParameters(Model) [[$bw Net] Name]]
                $bw -set WireModelName $MGC::WireBond::WBParameters(Model)
            }

            $::ediu(pcbDoc) TransactionEnd True
            GUI::StatusBar::UpdateStatus -busy off
        }

        ##
        ##  MGC::WireBond::ExportWireModel
        ##
        proc ExportWireModel { { wb "" } } {
            variable Units
            variable WBRule

            if { $wb == "" } {
                set wb [tk_getSaveFile -filetypes {{WB .wb} {All *}} \
                    -initialfile [format "%s.wb" $WBRule(Name)] -defaultextension ".wb"]
            }

            if { $wb == "" } {
                GUI::Transcript -severity warning -msg "No Placement file specified, Export aborted."
                return
            }
        
            #  Write the wire model to the file

            set f [open $wb "w+"]
            puts $f $WBRule(Value)
            close $f

            GUI::Transcript -severity note -msg [format "Wire Model successfully exported to file \"%s\"." $wb]

            return
        }
    }
}
