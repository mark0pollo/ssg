;+
; $Id: ssg_get_dispers.pro,v 1.5 2002/12/05 03:37:58 jpmorgen Exp $

; ssg_get_dispers.  Use comp lamp spectra to find dispersion relation

;-

function delta_spec, X, params, N_continuum=N_continuum

  n_params = N_elements(params)
  Yaxis = fltarr(N_elements(X))
  if N_elements(params) eq 0 then return, Yaxis

  dps = params                  ; delta function paramters
  if keyword_set(N_continuum) then begin
     if n_params lt N_continuum then message, 'ERROR: not enough parameters specified (' + string(n_params) + ') for N_continuum = ' + string(N_continuum)
     for n=0,N_continuum-1 do begin
        Yaxis = Yaxis + params[n]*X^n
     endfor
     dps = params[N_continuum:n_params-1]
  endif

  ;; Collect parameters into form that deltafn can use
  if N_elements(dps) mod 2 ne 0 then message, 'ERROR: wrong number of parameters.  Must have N_continuum continum parameters (polynomial assumed) and an even number of deltafuction parameters after that (X,Y)'
  n_lines = N_elements(dps)/2
  Xs = fltarr(n_lines)
  Yvals = Xs
  for i=0, n_lines-1 do begin
     Xs[i] = dps[2*i]
     Yvals[i] = dps[2*i+1]
  endfor

  return, deltafn(Xs, Yvals, Yaxis)
end

function voigt_spec, X, params, dparams, N_continuum=N_continuum

  n_params = N_elements(params)
  Yaxis = fltarr(N_elements(X))
  if N_elements(params) eq 0 then return, Yaxis

  vps = params                  ; voigt parameters
  if keyword_set(N_continuum) then begin
     if n_params lt N_continuum then message, 'ERROR: not enough parameters specified (' + string(n_params) + ') for N_continuum = ' + string(N_continuum)
     for n=0,N_continuum-1 do begin
        Yaxis = Yaxis + params[n]*X^n
     endfor
     vps = params[N_continuum:n_params-1]
  endif

  return, voigtfn(vps, X, Yaxis)
end

;; Given an intitial dispersion, whose higher order terms we will not
;; modify, return a dispersion whose 0th order term is modified so
;; that pixel reads line wavelength
function align_disp, in_disp, line, pixel, ref_pixel
  disp=in_disp
  order = N_elements(disp)-1
  old_val = 0
  for di = 0,order do begin
     old_val = old_val + disp[di]*(pixel-ref_pixel)^di
  endfor
  disp[0] = disp[0] - old_val + line
  return, disp
end

;; make associations between lists.  list2, or the longer list, is
;; assumed to be the master list.  The indecies of list1 that reflect
;; the best matches to list2 are returned.  min_diff is the
;; cummulative difference between the lists in the best case match
function list_associate, list, master_list, diffs=diffs
  nl = N_elements(list)
  nml = N_elements(master_list)
  if nl gt nml then $
    message, 'ERROR: master list must be the same size or greter than list'
  associations = intarr(nl)

  ;; Make an array that has all the differences between the elements
  ;; of two lists.  In principle, the lists do not have to be sorted.
  diffarray = fltarr(nl, nml)
  for i = 0,nl-1 do begin
     diffarray[i,*] = abs(master_list[*] - list[i])
  endfor

  ;; Now systematically match our lits using the minima in diffarray.
  ;; The mapping must be one to one, so blank out the parts of the
  ;; array that we have already used.  In order to avoid false matches
  ;; by a change close association early in the list, loop through all
  ;; possible combinations and take the one that minimizes the total
  ;; difference.

  min_diffs = fltarr(nl)
  for outer_loop = 0, nl-1 do begin
     ;; Start by finding the closest match to the current outer_loop
     ;; list element
     da = diffarray             ; Start with a fresh diffarray each time
     min_diffs[outer_loop] = min(da[outer_loop, *], iml)
     da[outer_loop, *] = !values.f_nan
     da[*, iml] = !values.f_nan
     ;; Now let the rest fall into place for this iteration
     for mdi = 1, nl-1 do begin
        min_diffs[outer_loop] = min_diffs[outer_loop] + min(da, min_idx, /NAN)
        ;; Unwrap 1D array index into 2D version so we can blank out
        ;; used part of da
        il = min_idx[0] mod nl
        iml = fix(min_idx[0]/nl)
        da[il, *] = !values.f_nan
        da[*, iml] = !values.f_nan
     endfor
  endfor
  ;; Now see which iteration gave the best overall answer and use it
  ;; to generate the final association list
  min_diff = min(min_diffs, outer_loop)
  da = diffarray
  min_diff = min(da[outer_loop, *], iml)
  associations[il] = iml
  da[il, *] = !values.f_nan
  da[*, iml] = !values.f_nan
  ;; Now let the rest fall into place
  diffs = fltarr(nl)
  for mdi = 1, nl-1 do begin
     diffs[mdi] =  min(da, min_idx, /NAN)
     il = min_idx[0] mod nl
     iml = fix(min_idx[0]/nl)
     associations[il] = iml
     da[il, *] = !values.f_nan
     da[*, iml] = !values.f_nan
  endfor

  return, associations

end

function line_correlate, in_disp, no_dp, line_pix=line_pix, line_list=line_list, line_stengths=line_strengths, ref_pixel=ref_pixel, bad_fraction=bad_fraction

;   wspan = in_disp[1] * npts
;   wmin = in_disp[0] - wspan/2.
;   wmax = wmin + wspan
;   atlas_idx = where(line_list ge wmin and line_list lt wmax, $
;                     n_expected_lines)
;   if n_expected_lines eq 0 then return, !values.f_nan
  
;  plot,line_pix, line_list[atlas_idx], xstyle=2, ystyle=2, $
;       yrange=[min(line_list[atlas_idx]),max(line_list[atlas_idx])], $
;       psym=asterisk
  

  ;; Make predicted line list and match lines to those in the atlas
  ;; line list (line_list)
  pred_lines = make_disp_axis(in_disp, line_pix, ref_pixel)
  n_fit_lines = N_elements(pred_lines)
  n_line_list = N_elements(line_list)
  diffarray = dblarr(n_fit_lines, n_line_list)
  for i=0,n_fit_lines-1 do begin
     diffarray[i,*] = abs(line_list[*] - pred_lines[i])
  endfor
  min_dists = dblarr(n_fit_lines)
  for i=0,n_fit_lines-1 do begin
      min_dists[i] = min(diffarray, min_idx, /NAN)
      ;; Unwrap the index to get a 2D coordinate again.
      ifit_line = min_idx[0] mod n_fit_lines
      iline_list = fix(min_idx[0]/n_fit_lines)
      diffarray[ifit_line, *] = !values.f_nan
      diffarray[*, iline_list] = !values.f_nan
   endfor
   ;; Inevitable there will be some line misidentifications.  That
   ;; means the last few distances will be bad.  Let's hack of 10% for
   ;; good measure
;   if NOT keyword_set(bad_fraction) then bad_fraction = .5
;   temp = min_dists[0:fix((1-bad_fraction)*n_fit_lines)]
;   min_dists= temp
   
   ;; Debugging
   ;plot, min_dists

;   bad_idx = where(min_dists gt max(pred_lines) - min(pred_lines), count)
;   if count gt 0 then $
;     min_dists[n_fit_lines-count-1:n_fit_lines-1] = 0

   return, total(min_dists^2)
end


function comp_correlate, in_disp, no_dp, spec=spec, line_list=line_list, line_stengths=line_strengths

  ;; Make this function usable in a variety of contexts later
  if n_params() eq 2 then begin
     if N_elements(in_disp) eq N_elements(no_dp) then $
       message, 'ERROR: I think you are asking me to calculate a derivative of the parameters for tnmin.  I don''nt know how to do this.  Make sure you specify /AUTODERIVATIVE with tnmin'
  endif

  if NOT keyword_set(spec) then message, 'ERROR: I need a spectrum to compare things with'
  if NOT keyword_set(line_list) then message, 'ERROR: I need a line list to compare things with'

  num_lines = N_elements(line_list)
  if NOT keyword_set(line_strengths) then begin
     line_strengths = spec
  endif 


  npts = N_elements(spec)
  disp_axis = dblarr(npts)
  pix_axis = indgen(npts) - npts/2
  order = N_elements(in_disp)
  for di = 0,order-1 do begin
     disp_axis = disp_axis + in_disp[di]*pix_axis^di
  endfor
  
  y=fltarr(npts)
  y = deltafn(line_list, line_strengths, y, Xaxis = disp_axis)


;   print, in_disp
;   print,minmax(disp_axis)
;   print,minmax(y)
;   print,minmax(spec)
  
  plot,disp_axis, y
  oplot,disp_axis, spec, linestyle=2
;  wait, 0.5
  return, total(y*spec,/NAN)

end


pro ssg_get_dispers, indir, VERBOSE=verbose, showplots=showplots, TV=tv, atlas=atlas, dispers=disp, order=order, N_continuum=N_continuum, noninteractive=noninteractive, frac_lines=frac_lines, width_fixed=width_fixed, write=write, review=review, cutval=cutval, MAXITER=maxiter

;  ON_ERROR, 2
  cd, indir

  if NOT keyword_set(atlas) then atlas='/home/jpmorgen/data/ssg/reduced/thar_list'
  if NOT keyword_set(frac_lines) then frac_lines = 0.6
  if NOT keyword_set(cutval) then cutval = 3 ; cut for discarding bad lines
  if keyword_set(width_fixed) then begin
     if N_elements(width_fixed) eq 1 then width_fixed = [1,1]
  endif
  if NOT keyword_set(width_fixed) then width_fixed = [0,0]
  
  if NOT keyword_set(order) then order=2
  if NOT keyword_set(disp) then disp = 6300

  ;; Make sure we don't modify any external variables and build up a
  ;; list of defaults coefs politely
  in_disp = disp
  if N_elements(in_disp) eq 1 then in_disp = [in_disp, 0.055]
  while N_elements(in_disp) lt order+1 do $
    in_disp = [in_disp, 0]

  ;; Be careful with type conversion so everything ends up double.  By
  ;; default we do a 2nd order polynomial fit, unless someone
  ;; explicitly sets order=2
  dispers = dblarr(order+1)
  ;; For some of the code to work conveniently, there has to be at
  ;; least a constant continuum
  if NOT keyword_set(N_continuum) then N_continuum = 1
  if NOT keyword_set(MAXITER) then maxiter=20

  silent = 1
  if keyword_set(verbose) then silent = 0

  plus = 1
  asterisk = 2
  dot = 3
  diamond = 4
  triangle = 5
  square = 6
  psym_x = 7

  solid=0
  dotted=1
  dashed=2
  dash_dot=3
  dash_3dot = 4
  long_dash=5

  ;; Read in whole atlas
  openr, lun, /get_lun, atlas
  num_lines=0
  ;; Count number of lines.  I thought there was an easy way to do
  ;; this, but couldn't find it in a hurry
  while NOT EOF(lun) do begin
     readf, lun, junk
     num_lines = num_lines + 1
  endwhile
  close, lun
  num_lines = num_lines - 1
  ;; Now really read in atlas
  line_list = dblarr(num_lines)
  openr, lun, /get_lun, atlas
  for li = 0,num_lines - 1 do begin
     readf, lun, temp
     line_list[li]=temp
  endfor
  close, lun
  ;; If we ever get some line strengths this will help, but I think
  ;; that with step-by-step correlation, we can work around that
  line_strengths = fltarr(num_lines)
  line_strengths[*] = 1

  dbclose ;; Just in case
  dbname = 'ssg_reduce'
  dbopen, dbname, 0
  ;; Get all the files in the directory so we can mark camrot as not
  ;; measured on the ones where we can't measure it.
  entries = dbfind("typecode=2", $
                   dbfind("bad<2047", $ ; < is really <=
                          dbfind(string("dir=", indir))))

  dbext, entries, "fname, nday, date, m_dispers", $
         files, ndays, dates, disp_arrays
  nf = N_elements(files)

  jds = ndays + julday(1,1,1990)
  ;; Use the last file of the day since if you take biases in the
  ;; afternoon, UT date hasn't turned over yet.
  temp=strsplit(dates[nf-1],'T',/extract) 
  utdate=temp[0]
  this_nday = median(ndays)     ; presumably this will throw out anything taken at an odd time

  
  files=strtrim(files)

  if NOT keyword_set(review) then begin ; We really want to do all the fitting

     window,6

     ngood = 0
     err=0

     for i=0,nf-1 do begin

        message, 'Looking at ' + files[i], /CONTINUE
;     CATCH, err
        if err ne 0 then begin
           message, /NONAME, !error_state.msg, /CONTINUE
           message, 'skipping ' + files[i], /CONTINUE
        endif else begin
           im = ssgread(files[i], hdr, /DATA)
           asize = size(im) & nx = asize(1) & ny = asize(2)

           ssg_spec_extract, im, hdr, spec, xdisp, /TOTAL

           npts = N_elements(spec)
           pix_axis = indgen(npts)

           ;; Remove NAN and 0 points, which give mpfit problems.  -->
           ;; Make sure our spectral axis starts at 0, though
           idx = 0
           while finite(spec(idx)) eq 0 or spec(idx) eq 0 do begin
              idx = idx+1
           endwhile
           left_idx = idx
           idx = npts-1
           while finite(spec(idx)) eq 0 or spec(idx) eq 0 do begin
              idx = idx-1
           endwhile
           right_idx = idx

           ;; IMPORTANT!!  I want to define ref_pixel to always be the
           ;; middle pixel of the original image.  That means I need
           ;; to account for the offset induced by chopping the
           ;; spectrum short.
           ref_pixel = npts/2. - left_idx
           temp = pix_axis[left_idx:right_idx] & pix_axis = temp
           temp =     spec[left_idx:right_idx] &     spec = temp

           ;; CAUTION, the reference for pix_axis and all the dispersion
           ;; calculations is the center of the array, not the edge

           ;; start each file afresh
           dispers[*] = in_disp[*]

           ;; Now choose our likely window of lines, being liberal
           ;; with the window so we get matches.  
           wbounds = make_disp_axis(dispers, [-npts, npts*2], ref_pixel)
           atlas_idx = where(line_list ge wbounds[0] and $
                             line_list lt wbounds[1])
           ;; But calculate the number of expected lines more
           ;; realistically
           wbounds = make_disp_axis(dispers, [0, npts-1], ref_pixel)
           junk = where(line_list ge wbounds[0] and $
                        line_list lt wbounds[1], $
                        n_expected_lines)

           n_expected_lines = fix(frac_lines * n_expected_lines)

           if n_expected_lines lt order - 1 then $
             message, 'ERROR: by only using ' + string(frac_lines) + '* the number of atlas lines, I cannot constrain a ' + string(order) + ' order dispersion solution.  Consider frac_lines=1 or lowering the order'


           ;; Fit one line at a time, starting from the highest.
           ;; Fit the next line using the residuals, etc.
           ;; Fo one last fit with everything in to make sure thing
           ;; settle.

           n_params = 0
           n_lines = 0
           vps = 0
           param_per_voigt = 4
           old_red_chisq = 1

           params = dblarr(N_continuum)
           parinfo = replicate({fixed:0, $
                                limited:[0,0], $
                                limits:[0.D,0.D], $
                                parname:'poly continuum'}, $
                               N_continuum)

           model_spec=dblarr(right_idx-left_idx+1)

           ;; Fit Voigt functions to the comp spectrum
           !p.multi = [0,0,2]
           repeat begin
              residual = spec - model_spec
              next_max = max(residual, next_maxx, /NAN)
              
              ;; Instead of accumulating the parameters while fitting,
              ;; just do them one at a time
              params = [params[0:N_continuum-1], $
                        next_maxx[0], $ ; center
                        1.5, $  ; Gauss FWHM
                        0, $    ; Lor width
                        next_max[0]] ; Area
              
              ;; Put on some constraints for narrow comp lines
              parinfo = [parinfo[0:N_continuum-1], $
                         {fixed:0, limited:[0,0], limits:[0.D,0.D], parname:'Center'}, $
                         {fixed:width_fixed[0], limited:[1,1], limits:[0.D,4.D], parname:'Gauss FWHM'}, $
                         {fixed:width_fixed[1], limited:[1,1], limits:[0.D,4.D], parname:'Lor Width'}, $
                         {fixed:0, limited:[0,0], limits:[0.D,0.D], parname:'Area'}]

              to_pass = { N_continuum:N_continuum }
              params = mpfitfun('voigt_spec', pix_axis, residual, sqrt(spec), $
                                params, FUNCTARGS=to_pass, AUTODERIVATIVE=1, $
                                PARINFO=parinfo)

              n_lines = n_lines + 1
              n_params = N_elements(params)
              if N_elements(vps) le 1 then begin ; Voigt parameters
                 vps = params[N_continuum:n_params-1]
              endif else begin
                 vps = [vps, params[N_continuum:n_params-1]]
              endelse

              model_spec = voigt_spec(pix_axis, $
                                      [params[0:N_continuum-1], vps], $
                                      N_continuum=N_continuum)
              red_chisq = total((spec[*] - model_spec[*])^2)/ $
                          (N_continuum + n_lines*param_per_voigt)

              end_of_loop = old_red_chisq ge red_chisq or $
                            n_lines eq n_expected_lines

              if end_of_loop then begin
                 ;; Do one last fit with all parameters free
                 final_params = mpfitfun('voigt_spec', $
                                         pix_axis, spec, sqrt(spec), $
                                         [params[0:N_continuum-1], vps], $
                                         FUNCTARGS=to_pass, AUTODERIVATIVE=1, $
                                         PERROR=perror, MAXITER=maxiter)
                 model_spec = voigt_spec(pix_axis, params, N_continuum=N_continuum)
              endif
              if end_of_loop or keyword_set(showplots) then begin
                 wset,6
                 plot, pix_axis, spec, $
                       title=string("Spectrum of comp ", files[i]), $
                       xtitle='Pixels', $
                       ytitle=string(sxpar(hdr, 'BUNIT'), 'Solid=data, dotted=model')
                 oplot, pix_axis, model_spec, linestyle=dotted
                 plot, pix_axis, residual, $
                       title=string("Fit residual "), $
                       xtitle='Pixels ref to center of image', $
                       ytitle=string(sxpar(hdr, 'BUNIT'))
              endif
           endrep until end_of_loop

           
           !p.multi = 0

           if n_lines ne n_expected_lines then $
             message, 'Unsure how to proceed'


           ;; Extract line pixel values from parameter list
           ;; Strip off continuum
           n_params = N_elements(final_params)
           vps = final_params[N_continuum:n_params-1]
           verrors = perror[N_continuum:n_params-1]
           Xs = dblarr(n_lines)
           dXs = dblarr(n_lines)
           areas = fltarr(n_lines)
           for li=0, n_lines-1 do begin
              Xs[li] = vps[4*li]
              areas[li] = vps[4*li+3]
              dXs[li] = verrors[4*li]
           endfor

           line_sort=sort(Xs)

           ;; tnmin is having a hard time finding the best fit
           ;; spontaneously, so go through each line and see how things
           ;; look when we line up on it.  This amounts to a preliminary
           ;; grid search on the reference wavelength
           first_pass = fltarr(n_lines, n_expected_lines)
           tdisp = dispers
           for icomp=0,n_lines-1 do begin
              for iatlas=0,n_expected_lines-1 do begin
                 tdisp = align_disp(dispers, line_list[atlas_idx[iatlas]], $
                                    Xs[icomp], ref_pixel)

           associations = list_associate(close_match, line_list, diffs=diffs)
           bad_idx = where(diffs-median(diffs) gt cutval*meanabsdev(diffs), $
                           count)

                 first_pass[icomp, iatlas] = $
                   line_correlate(tdisp, line_pix=Xs, $
                                  line_list=line_list[atlas_idx], $
                                  ref_pixel=ref_pixel)
                 ;;print, icomp, iatlas, first_pass[icomp, iatlas]
              endfor
           endfor
           temp = min(first_pass, min_idx, /NAN)
           ;; Unwrap the index to get a 2D coordinate again.
           ifit_line = min_idx[0] mod n_lines
           iline_list = fix(min_idx[0]/n_expected_lines)

           ;; Initialize the dispersion on our best first guess
           dispers = align_disp(dispers, line_list[atlas_idx[iline_list]], $
                                Xs[ifit_line], ref_pixel)

           ;; For display purposes (and maybe fitting later), let's see
           ;; if we can't associate the comp lines to the atlas at this point

           close_match = make_disp_axis(dispers, Xs, ref_pixel)
           
           

           associations = list_associate(close_match, line_list, diffs=diffs)
           bad_idx = where(diffs-median(diffs) gt cutval*meanabsdev(diffs), $
                           count)
           if count gt 0 then Xs[bad_idx] = !values.f_nan

          coefs = jpm_polyfit(Xs[line_sort]-ref_pixel, $
                               line_list[associations[line_sort]], order, $
                               title=string("Dispersion relation for comp ", files[i]), $
                               xtitle='Pixels ref to center of image', $
                               ytitle='Best guess association to atlas line', $
                               noninteractive=noninteractive)
           print, coefs
           disp_arrays[0:order,i] = coefs
           ngood = ngood + 1
        endelse ;; CATCH if err
     endfor ;; all files in directory
     CATCH, /CANCEL
     if ngood eq 0 then message, 'ERROR: no properly prepared files found, database not updated'
  
  endif ;; not reviewing

  if NOT keyword_set(noninteractive) then begin
     marked_ndays = ssg_mark_bad(ndays, rotate(disp_arrays,3), $
                                 title=string('Dispersion coefs in ', indir), $
                                 xtickunits='Hours', $
                                 xtitle=string('UT time (Hours) ', utdate), $
                                 ytitle='Coef value', $
                                 window=7)

     dbclose

     bad_idx = where(finite(marked_ndays) eq 0, count)
     ;; Beware the cumulative effect here
     if count gt 0 then badarray[bad_idx] = badarray[bad_idx] + 16384

     if NOT keyword_set(write) then begin
        for ki = 0,1000 do flush_input = get_kbrd(0)
        repeat begin
           message, /CONTINUE, 'Write these values to the database?([Y]/N)'
           answer = get_kbrd(1)
           if byte(answer) eq 10 then answer = 'Y'
           answer = strupcase(answer)
        endrep until answer eq 'Y' or answer eq 'N'
        for ki = 0,1000 do flush_input = get_kbrd(0)
        if answer eq 'Y' then write=1
     endif

  endif ;; interactive


  if keyword_set(write) then begin
     oldpriv=!priv
     !priv = 2
     dbopen, dbname, 1
     dbupdate, entries, 'm_dispers', disp_arrays
     dbclose
     !priv=oldpriv
     message, /INFORMATIONAL, 'Updated measured dispersion information rotation in ' + dbname
  endif ;; write


  ;; For convenience 
  message, /INFORMATIONAL, 'Directory is set to ' + indir

end
