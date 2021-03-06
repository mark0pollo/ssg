;+
; NAME: ssg_ana_close_lines
;
; PURPOSE: Plot and analyze line parameters that are close to each
; other to help find stable parameter values.  Relies on .sav file
; from ssg_fit2ana 
;
; CATEGORY:
;
; CALLING SEQUENCE:
;
; DESCRIPTION:
;
; INPUTS:
;
; OPTIONAL INPUTS:
;
; KEYWORD PARAMETERS:
;
; OUTPUTS:
;
; OPTIONAL OUTPUTS:
;
; COMMON BLOCKS:  
;   Common blocks are ugly.  Consider using package-specific system
;   variables.
;
; SIDE EFFECTS:
;
; RESTRICTIONS:
;
; PROCEDURE:
;
; EXAMPLE:
;
; MODIFICATION HISTORY:
;
; $Id:$
;
; $Log:$
;-

;; Helper function for ssg_ana_close_lines
;; Accepts results of previous filtering (if any) and applies new
;; filter.  Return value of function is indices into original test
;; result array of filter
function ssg_ana_close_lines_filter, $
   test_results, $ ;; argument to where
   ngood_pts, $    ;; number of good points (return value)
   good_pts_idx=o_good_pts_idx, $ ;; result of previous filter
   bad_pts_idx=bad_pts_idx, $     ;; idx of bad points (return value)
   nbad_pts=nbad_pts             ;; number of bad points (return value)

  ;; Check input
  if N_elements(test_results) eq 0 then $
     message, 'ERROR: no test results.  Pass the whole array of par_values lt <filter value>'
  
  ;; Initialize for our first time through assuming all pts are good
  if N_elements(o_good_pts_idx) eq 0 then $
     o_good_pts_idx = lindgen(N_elements(test_results))
  ;; Handle the case where we were handed no good points (where of
  ;; previous run returns -1)
  if o_good_pts_idx[0] eq -1 then begin
     ngood_pts = 0
     nbad_pts = N_elements(test_results)
     bad_pts_idx = lindgen(nbad_pts)
     return, -1
  endif ;; no good points handed to us

  ;; If we made it here, we have a meaningful test to do

  ;; Apply our test results, but only for the points of the previous filter
  good_pts_idx = $
     where(test_results[o_good_pts_idx], $
           ngood_pts, $
           complement=bad_pts_idx, ncomplement=nbad_pts)
  ;; unwrap
  if ngood_pts gt 0 then $
     good_pts_idx = o_good_pts_idx[good_pts_idx]

  return, good_pts_idx

end ;; ssg_ana_close_lines_filter

pro ssg_ana_close_lines, $
   fname, $
   lparinfo_in=lparinfo_in, $
   new_lparinfo_fname=new_lparinfo_fname, $
   noninteractive=noninteractive, $
   chi2_cut=chi2_cut, $  ;; exclude from parameter median/stdev
   dw_cut=dw_cut, $      ;; exclude from parameter median/stdev
   DOWL_cut=DOWL_cut, $  ;; exclude from parameter median/stdev
   ew_err_cut=ew_err_cut, $ ;; percent of ew for [GL]w vs ew plots
   single_object=single_object, $;; group all object lines together
   close_limit=close_limit, $    ;; for filtering Gw and Lw, how close to come to limit in fraction of value
   ew_puff=ew_puff	;; amount to puff out ew limits from stdev in units of stdev

  init = {ssg_sysvar}
  init = {tok_sysvar}

  ;; Restore our sssg_ana_parinfo.  Let IDL raise the error if file
  ;; not found
  restore, fname, /relaxed_structure_assignment
  ;; Sanity checks
  N_sssg_ana_parinfo = N_elements(sssg_ana_parinfo) 
  if N_sssg_ana_parinfo eq 0 then $
     message, 'ERROR: no saved parinfo found'

  ;; Get the indices into our line center parameters, making sure to
  ;; avoid the end markers
  lc_idx = where(sssg_ana_parinfo.pfo.status ne !pfo.inactive and $
                 sssg_ana_parinfo.sso.ttype eq !sso.center and $
                 sssg_ana_parinfo.sso.ptype eq !sso.line, count)
  if count eq 0 then $
     message, 'ERROR: no lines found'

  ;; If we made it here, we have some business to do.

  ;; Set default values

  if NOT keyword_set(chi2_cut) then $
     chi2_cut = 5
  if NOT keyword_set(dw_cut) then $
     dw_cut = 10
  if NOT keyword_set(DOWL_cut) then $
     DOWL_cut = 50
  if NOT keyword_set(ew_err_cut) then $
     ew_err_cut = 0.6
  if NOT keyword_set(close_limit) then $
     close_limit = 0.05
  if NOT keyword_set(ew_puff) then $
     ew_puff = 1.2

  ;; Set up for color plot with simple tek_color color table
  color
  ;; Be polite with the color table
  tvlct, user_r, user_g, user_b, /get
  tek_color

  ;; Get our Doppler groups (dgs) set up.  dgs are ephemeral, so they
  ;; need to be assigned and stored in the sso_sysvar pointer system
  ;; to work properly.  But previous runs can mess up our numbering
  ;; scheme which sets our colors, below, so clear things out first
  ;; and set them up fresh
  sso_dg_assign, /clear
  
  ;; Before we do this, check to see if we want to analyze all our
  ;; objects together
  if keyword_set(single_object) then begin
     ;; Tweak the non-sun and non-earth path elements to be the
     ;; generic object
     for ip=0,N_elements(sssg_ana_parinfo)-1 do begin
        obj_idx = where(sssg_ana_parinfo[ip].sso.path gt !eph.earth, count)
        if count eq 0 then $
           CONTINUE
        sssg_ana_parinfo[ip].sso.path[obj_idx] = !eph.obj
     endfor ;; each
  endif ;; making one generic object

  sso_dg_assign, sssg_ana_parinfo

  ;; Get a unique list of dgs in the ssg_ana_parinfo, since these are
  ;; the ones we want to key in on
  dgs = sssg_ana_parinfo[lc_idx].sso.dg
  dgs = dgs[uniq(dgs, sort(dgs))]
  N_dgs = N_elements(dgs)
  
  ;; Get our original line list, lparinfo for comparing to the final
  ;; fit and modifying for the next fit
  if keyword_set(lparinfo_in) then begin
     restore, lparinfo_in, /relaxed_structure_assignment
  endif else begin
     ;; make sure we read a fresh copy off the disk each time, since
     ;; we fiddle with it 
     ssg_lparinfo, [6280, 6320], /reread
     lparinfo = *!ssg.lparinfo
  endelse
  ;; The lparinfo uses a general !sso.obj path element.  Get those
  ;; Doppler groups assigned and fix them when I need them in the
  ;; plotting/analysis section, below
  sso_dg_assign, lparinfo
  ;; Copy the original lparinfo so that we can install our improved
  ;; .value and .limits
  new_lparinfo = lparinfo
  ;; Mark all of our parameters as having "no opinion" and activate
  ;; them as we find them in our data.  First make sure not to tweak
  ;; the lparinfo end markers (not to be confused with the
  ;; ssg_fit1spec end markers).  See ssg_lparinfo.
  end_marker_idx = where(new_lparinfo.pfo.status eq !pfo.inactive and $
                         new_lparinfo.pfo.ftype eq !pfo.null and $
                         new_lparinfo.sso.ptype eq !sso.line and $
                         new_lparinfo.sso.ttype eq !sso.center, count)
  if count eq 0 then $
     message, 'ERROR: no end markers found in lparinfo'
  ;; Mark everything as "no_opinion"
  new_lparinfo.pfo.status = !pfo.no_opinion
  ;; Resurrect the end markers
  new_lparinfo[end_marker_idx].pfo.status = !pfo.inactive

  ;; Make array of Y-axes titles.  These are not stored in the
  ;; .parnames anywhere (see pfo_sso_funct.pro)
  yprint =  ['abs(Dop+dw)', 'ew', 'Gw', 'Lw']
  ytitles = yprint + ' (m'+ !tok.angstrom + ')'
  yprint += '(mA)'
  ytitles = ['Red chi!U2!D', ytitles, 'Close Line Metric']
  yprint = ['Red chi2', yprint, 'Close Line Metric']

  ;; Cycle through our sssg_ana_parinfo Doppler groups first, then
  ;; RWL, since at least for Io and airglow, [OI] is the same RWL.

  for idg=0, N_dgs-1 do begin
     print, "idg = ", idg
     tdg_idx = where(sssg_ana_parinfo[lc_idx].sso.dg eq dgs(idg), N_lines)
     if N_lines eq 0 then $
        message, 'ERROR: something is really wrong!  I should find the dg I just found!'
     ;; unwrap
     tdg_idx = lc_idx[tdg_idx]

     ;; Figure out what our object is in this path.  Put Jupiter in
     ;; just in case we ever fit scattered light off of Jupiter
     path = sso_dg_path(sssg_ana_parinfo[tdg_idx[0]].sso.dg)
     path_obj_idx = where(path ne !eph.sun and $
                          path ne !eph.earth and $
                          path ne !eph.jupiter and $
                          path ne !sso.aterm, $
                          N_obj)
     if N_obj gt 1 then $
        message, 'ERROR: I don''t expect more than one object (e.g. Io, Europa, etc.) on the path'
     ;; Translate the generic object dg in lparinfo to the specific
     ;; object dg of the sssg_ana_lparinfo, if we have one
     if N_obj eq 1 then begin
        obj = path[path_obj_idx]
        ;; Start from our sssg_ana_parinfo path
        lparinfo_path = path
        ;; Replace the object element with our generic lparinfo object code
        lparinfo_path[path_obj_idx] = !eph.obj
        ;; Find that dg
        lparinfo_dg = sso_path_dg(lparinfo_path)
        ;; Replace the dgs temporarily with the sssg_ana_parinfo dg
        lparinfo_dg_idx = where(lparinfo.sso.dg eq lparinfo_dg, count)
        if count eq 0 then $
           message, 'ERROR: no Doppler group paramters found.  This should not happen!'
        lparinfo[lparinfo_dg_idx].sso.dg = dgs(idg)        
     endif ;; translating lparinfo dg

     ;; Get a path listing
     path_names = strjoin(sso_dg_path(dgs(idg),  /names), '-')

     ;; Get our list of unique, sorted rest wavelengths
     RWLs = sssg_ana_parinfo[tdg_idx].sso.RWL
     RWLs = RWLs[uniq(RWLs, sort(RWLs))]

     ;; Go through each line in this Doppler group.
     for il=0, N_elements(RWLs)-1 do begin
        ;; Reset a flag for skipping lines for which we have no
        ;; meaningful data
        skip_line = 0
        ;; Handle the case when we are going back to a previous dg.
        ;; We want to start at the top of our previous dg's line list
        if keyword_set(dg_going_backward) then begin
           dg_going_backward = 0
           il = N_elements(RWLs)-1
        endif
        print, 'il =', il, '  idg = ', idg
        ;; Grab only the matching line centers
        tl_lc_idx = where(sssg_ana_parinfo[lc_idx].sso.dg eq dgs[idg] and $
                          sssg_ana_parinfo[lc_idx].sso.RWL eq RWLs[il], N_tlines)
        ;; Do our sanity checks
        if N_tlines eq 0 then $
           message, 'ERROR: not finding things I just found!'
        ;; Check to see if there are enough points to plot.
        if N_tlines lt 2 then begin
           ;;;; Check to see if we are going backward
           if keyword_set(going_backward) then $
              goto, go_backward
           CONTINUE
        endif ;; checking enough points to plot

        ;; If we made it here, we have enough points to plot.

        ;; unwrap
        tl_lc_idx = lc_idx[tl_lc_idx]
        bad_idx = where(floor(sssg_ana_parinfo[tl_lc_idx].sso.pfo.pfo.ftype) ne !pfo.voigt, count)
        if count gt 0 then $
           message, 'ERROR: I expect everything to com up Voigts right now'
        ;; Grab the same lines from lparinfo
        lp_lc_idx = where(lparinfo.sso.dg eq dgs[idg] and $
                          lparinfo.sso.RWL eq RWLs[il] and $
                          lparinfo.sso.ttype eq !sso.center and $
                          lparinfo.sso.ptype eq !sso.line, count)
        if count eq 0 then $
           message, 'ERROR: line not found in lparinfo'

        line_id = string(format='(a, " ", f9.4, " A ", a)', $
                         path_names, $
                         RWLs[il], $
                         sssg_ana_parinfo[tl_lc_idx[0]+1].parname)
        print, !tok.newline, line_id

        ;; Plot all parameters together
        ;; Having trouble with charsize returning to expectred value
        opcharsize = !p.charsize
        !P.charsize = 2
        !p.multi = [0, 1, 5]

        line_id = string(format='(a, " ", f9.4, " ", a, ", ", a)', $
                         path_names, $
                         RWLs[il], $
                         !tok.angstrom, $
                         sssg_ana_parinfo[tl_lc_idx[0]+1].parname)
        xtitle = string(format='("Delta observed wavelength (m", a, ") from ", a)', $
                        !tok.angstrom, $
                        line_id)
        
        ;; Make our xrange here to make sure everything lines up
        xrange = minmax(sssg_ana_parinfo[tl_lc_idx].sso_ana.DOWL[0])

        ;; Made a fancy extra plot with a close line metric
        ;; that didn't end up telling me anything
        ;;for iplot=0,2+!pfo.fnpars[!pfo.voigt]-1 do begin
        for iplot=0,1+!pfo.fnpars[!pfo.voigt]-1 do begin
           ;; Skip over the whole line if we run out of good parameters
           if keyword_set(skip_line) then $
              CONTINUE
           ipar = 0
           ylog = 0
           ;; First time through, create the default ptl_lc_idx,
           ;; the indices into sssg_ana_parinfo that we will
           ;; actually plot.  For reduced chi^2, plot everything
           ptl_lc_idx = tl_lc_idx
           case 1 of
              iplot eq 0 : begin
                 par_values = sssg_ana_parinfo[ptl_lc_idx+ipar].sso_ana.redchisq
                 err_values = 0
                 ;; Plot it on a log scale
                 ylog = 1
                 ;; Work on excluding bad points from our median and stdev
                 ;; Collect the idx into the line center parameters that have
                 ;; decent chi^2.  Erase our good_pts_idx from the last
                 ;; time around
                 junk = temporary(good_pts_idx)
                 good_pts_idx = $
                    ssg_ana_close_lines_filter( $
                    par_values lt chi2_cut, $
                    ngood_pts, $
                    $;good_pts_idx=good_pts_idx, $
                    bad_pts_idx=bad_pts_idx, $
                    nbad_pts=nbad_pts)

                 print, 'ndays with reduced chi2 gt ', chi2_cut
                 for ijunk=0,N_elements(bad_pts_idx)-1 do begin
                    print, sssg_ana_parinfo[ptl_lc_idx[bad_pts_idx[ijunk]]].ssg.nday, sssg_ana_parinfo[ptl_lc_idx[bad_pts_idx[ijunk]]].sso_ana.redchisq
                 endfor
              end
              iplot eq 1 : begin
                 ;; Plot only the good redchisq points
                 ptl_lc_idx = ptl_lc_idx[good_pts_idx]
                 ;; dw has two components, one from the Doppler and
                 ;; one from the dw.  Keep them seprate for printing
                 ;; purposes, but combine for filtering and plotting
                 ;; Regular dw
                 par_values = sssg_ana_parinfo[ptl_lc_idx+ipar].value
                 err_values = sssg_ana_parinfo[ptl_lc_idx+ipar].error
                 ;; Doppler
                 dpar_values = $
                    sssg_ana_parinfo[ptl_lc_idx+ipar].sso_ana.delta_dop
                 derr_values = $
                    sssg_ana_parinfo[ptl_lc_idx+ipar].sso_ana.err_delta_dop
                 ;; Combine Delta Doppler + dw to an absolute value
                 ;; metric for plotting and further calculation
                 par_values = abs(par_values) + abs(dpar_values)
                 err_values = sqrt(par_values^2 + par_values^2)
                 ylog = 1
                 ;; Exclude bad Delta Doppler + dw points.  Start with
                 ;; our good chi2 points (if any)
                 good_pts_idx = $
                    ssg_ana_close_lines_filter( $
                    par_values lt dw_cut, $
                    ngood_pts, $
                    $;good_pts_idx=good_pts_idx, $
                    bad_pts_idx=bad_pts_idx, $
                    nbad_pts=nbad_pts)
                 ;; Save these good_pts_idx for ew, Gw, Lw unwraping
                 ;; to ptl_lc_idx
                 plot_width_idx = ptl_lc_idx[good_pts_idx]
                 ;;;; Now that we have our filter set, plot the actual
                 ;;;; Doppler value
                 ;;par_values = dpar_values
                 ;;err_values = derr_values
              end
              2 le iplot and iplot le 4 : begin
                 ;; ew, Gw, Lw
                 ptl_lc_idx = plot_width_idx
                 ipar = iplot - 1
                 ;; Plot the value and error of our host line as a function
                 ;; DOWL to the 0th closest line
                 par_values = sssg_ana_parinfo[ptl_lc_idx+ipar].value
                 err_values = sssg_ana_parinfo[ptl_lc_idx+ipar].error

                 ;; Make sure X-axis and parameters line up.
                 xaxis = sssg_ana_parinfo[ptl_lc_idx].sso_ana.DOWL[0]

                 ;; Only include points that are outside +/- DOWL_cut
                 good_pts_idx = $
                    ssg_ana_close_lines_filter( $
                    abs(xaxis) gt DOWL_cut, $
                    ngood_pts, $
                    $;good_pts_idx=ptl_lc_idx, $
                    bad_pts_idx=bad_pts_idx, $
                    nbad_pts=nbad_pts)
              end
              iplot eq 5: begin
                 ipar = -1
                 ;; Metric for bad overlap:
                 ;; (ewcl - ewp)/ (DOWL + abs(Gwp - Gwcl))
                 ewp = sssg_ana_parinfo[ptl_lc_idx+1].value
                 dewp = sssg_ana_parinfo[ptl_lc_idx+1].error
                 ewcl = sssg_ana_parinfo[ptl_lc_idx+1].sso_ana.value[0]
                 dewcl = sssg_ana_parinfo[ptl_lc_idx+1].sso_ana.error[0]
                 ;; DOWL = xaxis, errors are negligible
                 Gwp = sssg_ana_parinfo[ptl_lc_idx+2].value
                 dGwp = sssg_ana_parinfo[ptl_lc_idx+2].error
                 Gwcl = sssg_ana_parinfo[ptl_lc_idx+2].sso_ana.value[0]
                 dGwcl = sssg_ana_parinfo[ptl_lc_idx+2].sso_ana.error[0]
                 ptl_lc_idx = plot_width_idx
                 par_values = (abs(ewcl) - abs(ewp)) / (abs(xaxis) + abs(Gwcl - Gwp))
                 err_values = $
                    par_values * $
                    sqrt((dewcl^2 + dewp^2) / (ewcl - ewp) + $
                         (dGwcl^2 + dGwp^2) / xaxis + abs(Gwcl - Gwp))
              end ;; close line metric
           endcase
           ;; For single parameters
           if ipar ge 0 then begin
              ;; If we don't have enough good points, we can't do
              ;; meaningful statistical analysis --> I would like to come
              ;; up with a beter fiducial than this, like a percentage of
              ;; all of the spectra fit or something like that.  But I
              ;; suppose if I have 5 good measurements, I can get an OK
              ;; median and stdev.  Don't bother plotting bad
              ;; plots anymore either.  Be careful with the case where we
              ;; find bad parameter mid-way through our line.  We want to
              ;; go back and mark the whole line as no_opinion

              ;; --> now that I am analyzing all of the moons, I need
              ;; to work on this to not keep resetting
              if ngood_pts lt 5 then begin
                 new_lparinfo[lp_lc_idx:lp_lc_idx+ipar].pfo.status = !pfo.no_opinion
                 skip_line = 1
                 CONTINUE ;; each parameter, so we need skip_line
              endif
              
              ;; If we made it here, we have the ability to do statistics
              ;; and will have some sort of an opinion about this
              ;; parameter.  Mark it as active in new_lparinfo
              new_lparinfo[lp_lc_idx+ipar].pfo.status = !pfo.active
           endif ;; single-parameter based

           ;; Since we have lots of measurements, many of which are
           ;; bogus, stick with median to get our best value
           med = median(par_values[good_pts_idx])
           ;; --> eventually I could upgrade this to through out
           ;; outliers and recalculate with mean, but I am not sure it
           ;; would work as well in this case as it did with biases
           stdev = stdev(par_values[good_pts_idx])
           print, format='(a16, " = ", f6.1, " +/-", f6.1)', $
                  yprint[iplot], med, stdev
           ;; For Doppler, print that separately
           if iplot eq 1 then begin
              dmed = median(dpar_values[good_pts_idx])
              dstdev = stdev(dpar_values[good_pts_idx])
              print, $
                 format='(a16, " = ", f6.1, " +/-", f6.1)', $
                 'Doppler (mA)', $
                 dmed, dstdev                 
              ;; convert back to km/s
              v2c = !ssg.c / median(sssg_ana_parinfo[ptl_lc_idx+ipar].sso.OWL)
              print, $
                 format='(a16, " = ", f6.1, " +/-", f6.1)', $
                 'Doppler (km/s)', dmed*v2c*!sso.dwcvt, dstdev*v2c*!sso.dwcvt
           endif ;; print Doppler value
           ;; Record our meaningful median and stdev values into the
           ;; .value and .limits of the new_lparinfo.  We will display
           ;; and finalize this below.
           ;; Skip dw for now, since it is contaminated by Doppler,
           ;; but note that we marked it as active, above
           if ipar gt 0 then begin
              new_lparinfo[lp_lc_idx+ipar].value = med
              new_lparinfo[lp_lc_idx+ipar].limits = med + [-stdev, stdev]
           endif ;; skipping dw

           ;; Skip plots in non-interactive case
           if NOT keyword_set(noninteractive) then begin
              ;; Cycle through the dgs of the close lines to plot each
              ;; one in a different color.  Start by making the plot
              ;; axes
              yrange = minmax(par_values)
              ;; Try to weed out some of the junky points
              ;; Sun Sep 13 08:19:08 2015  jpmorgen@snipe
              ;; See if limits solve this problem
              if ipar gt 0 then begin
                 ;;yrange = med + 3*[-stdev, stdev]
              endif
              if iplot eq 1 then $
                 yrange[0] = 0.01
              ;; Make sure X-axis and parameters line up.
              xaxis = sssg_ana_parinfo[ptl_lc_idx].sso_ana.DOWL[0]
              plot, xaxis, par_values, $
                    /nodata, ylog=ylog, $
                    xmargin=[12,3], $
                    xtitle=xtitle, $
                    ytitle=ytitles[iplot], $
                    psym=!tok.plus, $
                    xrange=xrange, xstyle=!tok.exact+!tok.extend, $
                    yrange=yrange, $
                    ystyle=!tok.exact+!tok.extend
              for ipdg=0, N_elements(dgs)-1 do begin
                 clp_idx = where(sssg_ana_parinfo[ptl_lc_idx].sso_ana.dg[0] $
                                 eq dgs[ipdg], count)
                 ;; Avoid trouble with not enough points
                 if count lt 2 then $
                    CONTINUE
                 ;; Don't unwrap.  clp_idx is the index into
                 ;; ptl_lc_idx+ipar, which is what xaxis and par_values
                 ;; were created from.  Take care of the case where
                 ;; color is wrapping
                 color = dgs[ipdg]
                 if color eq 0 then $
                    color++
                 oplot, xaxis[clp_idx], $
                        par_values[clp_idx], $
                        psym=!tok.plus, $
                        color=color
                 errplot, xaxis[clp_idx], $
                          par_values[clp_idx] + err_values[clp_idx]/2, $
                          par_values[clp_idx] - err_values[clp_idx]/2, $
                          color=color, width=0.001
              endfor ;; plotting each close line Doppler group by color

              ;; Plot cut values used to exclude bad events
              case iplot of
                 0 : oplot, !x.crange, replicate(chi2_cut, 2), $
                            linestyle=!tok.dash_dot
                 1 : oplot, !x.crange, replicate(dw_cut, 2), $
                            linestyle=!tok.dash_dot
                 else : begin
                    oplot, replicate(-DOWL_cut, 2), !y.crange, $
                           linestyle=!tok.dash_dot
                    oplot, replicate(DOWL_cut, 2), !y.crange, $
                           linestyle=!tok.dash_dot
                 end
              endcase
              oplot, !x.crange, replicate(med, 2), $
                     linestyle=!tok.dashed
              oplot, !x.crange, replicate(med + stdev, 2), $
                     linestyle=!tok.dotted
              oplot, !x.crange, replicate(med - stdev, 2), $
                     linestyle=!tok.dotted
              ;; Plot lparinfo value for ew, Gw, Lw
              if iplot gt 0 then begin
                 lval = lparinfo[lp_lc_idx+ipar].value
                 llimit0 = lparinfo[lp_lc_idx+ipar].limits[0]
                 llimit1 = lparinfo[lp_lc_idx+ipar].limits[1]
                 oplot, !x.crange, replicate(lval, 2), $
                        linestyle=!tok.solid
                 oplot, !x.crange, replicate(llimit0, 2), $
                        linestyle=!tok.dash_3dot
                 oplot, !x.crange, replicate(llimit1, 2), $
                        linestyle=!tok.dash_3dot
              endif ;;
           endif    ;; interactive

        endfor   ;; Each parameter

        ;; Make a nice menu for paging through the lines
        answer = ''
        if NOT keyword_set(noninteractive) then begin ;; and $
           ;;NOT keyword_set(skip_line) then begin
           message, /CONTINUE, 'Menu:'
           print, 'Next'
           print, 'Previous'
           print, 'free-Run'
           print, 'Quit in mid-run'
           answer = ''
           for ki = 0,1000 do flush_input = get_kbrd(0)
           repeat begin
              message, /CONTINUE, '[N], P, R, Q?'
              answer = get_kbrd(1)
              if byte(answer) eq 10 then answer = 'N'
              for ki = 0,1000 do flush_input = get_kbrd(0)
              answer = strupcase(answer)
           endrep until $
              answer eq 'N' or $
              answer eq 'P' or $
              answer eq 'R' or $
              answer eq 'Q'
           case answer of
              'N' : going_backward = 0 ;; Just let for loop continue
              'P' : begin
                 go_backward:
                 going_backward = 1
                 il -= 2
                 ;; Check to see if we are too low, in which case we
                 ;; trigger the end of the il loop and go to the
                 ;; previous idg
                 if il lt -1 then begin
                    il = N_elements(RWLs)-1
                    idg -= 2
                    dg_going_backward = 1
                 endif
                 ;; Unless we go below the 1st Doppler group.
                 if idg le -1 then begin
                    idg = 0                  ;; still in the idg loop
                    il = -1                  ;; cycle back to 0 (I think)
                    dg_going_backward = 0
                    going_backward = 0
                 endif
              end
              'R' : begin
                 noninteractive = 1
                 going_backward = 0
              end
              'Q' : begin
                 ;; Kick out the loops to finish
                 il = N_elements(RWLs)-1
                 idg = N_elements(dgs)-1
              end              
           endcase
        endif ;; Interactive
     endfor   ;; each line
     ;; Reset lparinfo dg to generic state
     if N_obj eq 1 then begin
        lparinfo[lparinfo_dg_idx].sso.dg = lparinfo_dg
     endif ;; translate lparinfo dg back to generic value
  endfor   ;; each Doppler group

  ;; The dreaded goto!  Saves a nested if-then to do cleanup stuff
  if answer eq 'Q' then $
     goto, finish

  ;; Plot Gw and Lw vs EW to see if I can firm up limits in the
  ;; various Doppler groups.  Get a list of the Doppler groups we are
  ;; interested in
  !p.multi = [0, 1, 4]
  sun_dg = sso_path_dg(sso_path_create([!eph.sun, !eph.obj, !eph.earth]))
  earth_dg = sso_path_dg(sso_path_create([!eph.earth, !eph.earth]))
  dgs = [sun_dg, earth_dg]
  ;; Make arrays to store our results in for putting into all of
  ;; the lines, even those we don't have opinions on
  width_av = dblarr(2,2)
  width_stdev = width_av
  for idg=0, N_elements(dgs)-1 do begin
     ;; Find all of the line centers for this Doppler group
     lp_lc_idx = where(new_lparinfo.pfo.status eq !pfo.active and $
                       new_lparinfo.sso.dg eq dgs[idg] and $
                       new_lparinfo.sso.ttype eq !sso.center and $
                       new_lparinfo.sso.ptype eq !sso.line, nlines)
     if nlines eq 0 then $
        message, 'ERROR: missing line center parameters in new_lparinfo'

     xaxis = new_lparinfo[lp_lc_idx+1].value
     xerr = new_lparinfo[lp_lc_idx+1].limits[1] - xaxis
     ;; There are some 0 EW lines?  6320.0000 and 6280.6245
     ;; filter by bad ew error.  Keep in mind ew is negative, except
     ;; airglow, which we want to cut out
     good_idx = where(abs(xerr/xaxis) lt ew_err_cut and $
                      new_lparinfo[lp_lc_idx+1].value lt 0, count)
     ;; Don't bother filtering if we don't have anything to plot
     if count lt 2 then begin
        message, 'WARNING: not enough good points found with ew filter criterion', /CONTINUE
        good_idx = lindgen(N_elements(xaxis))
     endif ;; filter check
     xaxis = -xaxis
     xtitle = '-' + ytitles[2]
     for ipar=2,3 do begin
        ;; Get lparinfo values and limits.  They should be the same, but
        ;; do median just in case
        lval = median(lparinfo[lp_lc_idx+ipar].value)
        llimit0 = median(lparinfo[lp_lc_idx+ipar].limits[0])
        llimit1 = median(lparinfo[lp_lc_idx+ipar].limits[1])

        yaxis = new_lparinfo[lp_lc_idx+ipar].value
        yerr = new_lparinfo[lp_lc_idx+ipar].limits[1] - yaxis
        ytitle = ytitles[ipar+1]
        ;; Tue Sep 22 10:41:21 2015  jpmorgen@snipe
        ;; Try another form of filtering seeing if we are pegged at/near
        ;; old lparinfo values
        cgood_idx = where(abs((llimit1 - yaxis[good_idx])/yaxis[good_idx]) gt close_limit and $
                          abs((llimit0 - yaxis[good_idx])/yaxis[good_idx]) gt close_limit, count)
        if count lt 2 then begin
           message, 'WARNING: not enough good points found with close_limit filter criterion', /CONTINUE
           cgood_idx = good_idx
        endif ;; filter check
        ;; unwrap
        good_idx = good_idx[cgood_idx]

        yrange = [min([yaxis[good_idx], llimit0]), $
                  max([yaxis[good_idx], llimit1])]
        plot, xaxis[good_idx], $
              yaxis[good_idx], $
              psym=!tok.asterisk, $
              xtitle=xtitle, ytitle=ytitle, /xlog, $
              yrange=yrange, $
              ystyle=!tok.extend;;+!tok.exact
        oploterror, xaxis[good_idx], $
                    yaxis[good_idx], $
                    xerr[good_idx], $
                    yerr[good_idx]
        med = median(yaxis[good_idx]) ;; too few points
        av = mean(yaxis[good_idx])    ;; what I want
        ;;stdev = stdev(yaxis[good_idx]) ;; too narrow
        stdev = mean(yerr[good_idx])
        ;; Make sure telluric lines have room to breath, since their
        ;; widths are really indicative of the spectrometer
        ;; performance
        if dgs[idg] eq earth_dg then $
           stdev = max(yerr[good_idx])
        oplot, 10^!x.crange, replicate(av, 2), $
               linestyle=!tok.dashed
        oplot, 10^!x.crange, replicate(av + stdev, 2), $
               linestyle=!tok.dotted
        oplot, 10^!x.crange, replicate(av - stdev, 2), $
               linestyle=!tok.dotted
        oplot, 10^!x.crange, replicate(lval, 2), $
               linestyle=!tok.solid
        oplot, 10^!x.crange, replicate(llimit0, 2), $
               linestyle=!tok.dash_3dot
        oplot, 10^!x.crange, replicate(llimit1, 2), $
               linestyle=!tok.dash_3dot
        print, av, '+/-', stdev
        ;; Following discussion around
        ;; Thu Aug 27 21:28:14 2015  jpmorgen@snipe
        ;; My favorite raw answers with ew_err_cut=0.4 are:
        ;; 126.92993+/-       17.028891
        ;; 33.470576+/-       17.296930
        ;; 44.447794+/-       12.269928
        ;; 30.487494+/-       9.1861917

        ;; Tue Sep 22 11:52:06 2015  jpmorgen@snipe
        ;; Next iteration, with potentially improved filtering of
        ;; values that pegged (close=0.10).  Note that we ignore
        ;; second parameter (Lw of solar lines)
        ;; 128.24271+/-       19.240070
        ;; 45.384685+/-       18.848046
        ;; 44.007828+/-       10.568762
        ;; 32.600012+/-       11.522068

        ;; I'd say that the widths are converging

        ;; Store results for application to all parameter, below
        width_av[idg, ipar-2] = av
        width_stdev[idg, ipar-2] = stdev
        
        ;; Except that I don't like how the solar Lorentzian turned
        ;; out.  See tweak below
     endfor ;; Gw, Lw
  endfor ;; idg

  ;; Reactivate the lines that we didn't measure.  They are still used
  ;; in initial dispersion calculations, so we want to put good dw and
  ;; width information into them
  idx = where(new_lparinfo.pfo.status eq !pfo.no_opinion, count)
  if count gt 0 then $
     new_lparinfo[idx].pfo.status = !pfo.active
  
  ;; Now put in our ew, Gw, and Lw information to all of the lines,
  ;; even our object line.  Also make sure we handle our airglow
  ;; line(s) properly.  To do this, tack on our object line to the
  ;; list of dgs we are handling
  obj_dg = sso_path_dg(sso_path_create([!eph.obj, !eph.earth]))
  dgs = [dgs, obj_dg]
  for idg=0, N_elements(dgs)-1 do begin
     ;; Find all of the line centers for this Doppler group
     lp_lc_idx = where(new_lparinfo.pfo.status eq !pfo.active and $
                       new_lparinfo.sso.dg eq dgs[idg] and $
                       new_lparinfo.sso.ttype eq !sso.center and $
                       new_lparinfo.sso.ptype eq !sso.line, nlines)
     if nlines eq 0 then $
        message, 'ERROR: missing line center parameters in new_lparinfo'

     ;; Adjust object line ew to have 0 lower bound and no upper bound
     if dgs[idg] eq obj_dg then begin
        for il=0, nlines-1 do begin
           new_lparinfo[lp_lc_idx[il]+1].limits = [0, 0]
           new_lparinfo[lp_lc_idx[il]+1].limited = [1, 0]
        endfor ;; each object line
     endif     ;; obj_dg
     for ipar=2,3 do begin
        ;; Fix object Lorentzian at 0 but keep Gw to measured value
        if dgs[idg] eq obj_dg then begin
           if ipar eq 3 then begin
              new_lparinfo[lp_lc_idx+ipar].value = 0
              new_lparinfo[lp_lc_idx+ipar].fixed = 1
           endif ;; Fix Lw at 0
           ;; Don't do any adjustments for other parameter(s)
           CONTINUE
        endif ;; obj_dg
        new_lparinfo[lp_lc_idx+ipar].fixed = 0
        value = width_av[idg, ipar-2]
        stdev = width_stdev[idg, ipar-2]
        new_lparinfo[lp_lc_idx+ipar].value = value
        ;; Puff up the limits by 2 sigma
        limits = value + 2.*[-stdev, stdev]
        ;; Make sure widths are >= 0
        limits[0] = max([0, limits[0]])
        new_lparinfo[lp_lc_idx+ipar].limits = limits
        ;; Tue Sep  1 10:36:11 2015  jpmorgen@snipe
        ;; Thinking I went too far with limiting Lw to non-zero values
        ;; Let Lw go to 0
        if ipar eq 3 then $
           new_lparinfo[lp_lc_idx+ipar].limits[0] = 0
     endfor ;; ipar

     ;; Fiddle with the telluric lines
     if dgs[idg] eq earth_dg then begin
        for il=0, nlines-1 do begin
           ;; For ew, put telluric limits back to original values, since
           ;; they are variable and I was reasonably happy with them.
           new_lparinfo[lp_lc_idx[il]+1].limits = $
              lparinfo[lp_lc_idx[il]+1].limits
           ;; Tue Sep 22 09:00:22 2015 jpmorgen@snipe [OI] 6300
           ;; airglow line actually has a non-negligible width (Wark
           ;; ApJ 131 p. 491).  Convolved with our typical O2 telluric
           ;; line width, which should be negligible, we get
           ;; 63.097147.  So puff it out a bit
           if new_lparinfo[lp_lc_idx[il]+1].value gt 0 then begin
              lparinfo[lp_lc_idx[il]+2].limits[1] = 100
           endif ;; airglow
        endfor ;; il
     endif ;; telluric lines

     ;; Solar lines, on the other hand, should be stable.  For the
     ;; initial fit (2015-09-04) I found that strong lines fall within
     ;; 2 sigma resonably nicely, but weak lines fall within 1-sigma.
     ;; In particular, weak lines where the other sigma would be above
     ;; 0.  I adjusted limits accordingly.  Using those limits, things
     ;; looked much more compact.
     if dgs[idg] eq sun_dg then begin
        new_lparinfo[lp_lc_idx+1].fixed = 0
        new_lparinfo[lp_lc_idx+1].limited = [1, 1]
        ;; IDL doesn't handle the implict array and structures
        ;; together
        for il=0,nlines-1 do begin
           limits = new_lparinfo[lp_lc_idx[il]+1].limits
           if limits[1] lt 0 then begin
              values = new_lparinfo[lp_lc_idx[il]+1].value
              limits -= values
              limits *= ew_puff
              limits += values
           endif ;; strong enough line to use 2-sigma limits
           ;; Make sure upper limit does not go above 0 (EWs are
           ;; negative!)
           limits[1] = min([0, limits[1]])
           new_lparinfo[lp_lc_idx[il]+1].limits = limits
        endfor ;; each line because struct and array get confused
     endif ;; solar ew
  endfor ;; idg


  
  ;; Fri Aug 28 07:48:47 2015  jpmorgen@snipe
  ;; Implement the results of our experiments on the
  ;; 2014-11-11_ssg_fit run

  ;; For all dw: we are going to fix our Doppler parameters to their
  ;; HORIZONS values in ssg_fit1spec.  Here we set the limits so
  ;; the lines can wiggle by 2mA
  lc_idx = where(new_lparinfo.pfo.status eq !pfo.active and $
                 new_lparinfo.sso.ttype eq !sso.center and $
                 new_lparinfo.sso.ptype eq !sso.line, N_lc)
  if N_lc eq 0 then $
     message, 'ERROR: no line centers found!'

  new_lparinfo[lc_idx].value = 0
  new_lparinfo[lc_idx].fixed = 0
  new_lparinfo[lc_idx].limited = [1, 1]
  new_lparinfo[lc_idx].limits = [-2d, 2d]


  ;; For solar lw, try re-fitting with minimum at 30mA, which I get
  ;; from the telluric lines and maximum at 200mA so I get a good
  ;; measurement from the large lines
  ;; Tue Sep  1 09:57:20 2015  jpmorgen@snipe
  ;; I am not sure that worked too well.  Set them back to previous limit
  sun_lc_idx = where(new_lparinfo.pfo.status eq !pfo.active and $
                     new_lparinfo.sso.ttype eq !sso.center and $
                     new_lparinfo.sso.ptype eq !sso.line and $
                     new_lparinfo.sso.dg eq sun_dg, $
                     N_lc)
  if N_lc eq 0 then $
     message, 'ERROR: no solar lines found!'
  
  new_lparinfo[sun_lc_idx+3].fixed = 0
  ;;new_lparinfo[sun_lc_idx+3].value = 90
  ;;new_lparinfo[sun_lc_idx+3].limits = [30, 200]
  new_lparinfo[sun_lc_idx+3].value = 10
  new_lparinfo[sun_lc_idx+3].limits = [0, 100]
           

  if keyword_set(new_lparinfo_fname) then begin
     lparinfo = new_lparinfo
     save, lparinfo, filename=new_lparinfo_fname
  endif

  finish:
  ;; Return color table to its original value
  tvlct, user_r, user_g, user_b
  !p.multi = 0
  !p.charsize = opcharsize
end

