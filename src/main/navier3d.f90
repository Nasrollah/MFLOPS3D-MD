program testnavier3d
  use command_line
  use class_navier_3D
  implicit none
  type(cmd_line) :: cmd
  type(navier3d) :: nav
  type(mpi_data) :: mpid
  integer(ik) :: nx,ny,nz
  integer(ik) :: ite
  integer(ik) :: i,j,k,iaux
  real(rk),allocatable :: uex(:,:,:,:), pex(:,:,:),vectorerror(:,:,:,:)
  real(rk) ::x,y,z,t,error,aux,time,errort,ref,reft
  integer(8) :: t1,t2,irate,subite

  !-> get command line informations
  call commandline(cmd)

  allocate(uex(cmd%nx,cmd%ny,cmd%nz,3),pex(cmd%nx,cmd%ny,cmd%nz))

  allocate(vectorerror(cmd%nx,cmd%ny,cmd%nz,5))
  !------------------------------------------------------------------------ 
  !-> pre-computation
  !------------------------------------------------------------------------ 
  call navier_initialization(cmd,mpid,nav)

  !-> write mesh
  call write_mesh('grid_x',nav%gridx,mpid)
  call write_mesh('grid_y',nav%gridy,mpid)
  call write_mesh('grid_z',nav%gridz,mpid)

  
  !------------------------------------------------------------------------ 
  !-> time loop
  !------------------------------------------------------------------------ 

  call system_clock(t1,irate)
temps:  do ite=1,nav%ntime
     !print*,mpid%coord
     
     if (ite==20) call system_clock(t1,irate)

     !-> time update
     call navier_time(nav)

subit:  do subite=1,nav%nsubite
     nav%subite=subite
     if (mpid%rank==0) print*,'Time : ',ite,subite

     !---------------------------------------------------------------------
!     if (mpid%rank==0) then
!        call color(ired);print'(a)','Time : ';call color(color_off)
!     endif
     !-> define bc
     call navier_bc_velocity(mpid,nav)
     
     !---------------------------------------------------------------------
     !-> compute rhs
     call navier_presolve_u(mpid,nav)
     call navier_presolve_v(mpid,nav)
     call navier_presolve_w(mpid,nav)

     !---------------------------------------------------------------------
     !-> solve intermediate u,v,w (pressure correction)

     if(nav%pt<=2) then
       if(nav%pt==1) call add_boundary_gradient(mpid,nav)
       call navier_solve_u(mpid,nav)
       call navier_solve_v(mpid,nav)
       call navier_solve_w(mpid,nav)
     endif

     call navier_presolve_phi(mpid,nav)
     call navier_bc_pressure(mpid,nav)
     !---------------------------------------------------------------------
     !-> solve pressure increment phi

     call navier_solve_phi(mpid,nav)

     !---------------------------------------------------------------------
     !-> compute u,v,w,p
     
     call navier_projection(mpid,nav)

     !---------------------------------------------------------------------
     !-> compute final u,v,w  (velocity correction)
     if(nav%pt>=3) then
       call navier_solve_u(mpid,nav)
       call navier_solve_v(mpid,nav)
       call navier_solve_w(mpid,nav)
     endif

testconv: if(subite>1)then

     nav%aux%f=0._rk
     nav%aux=derx(nav%dcx,nav%u(nav%it(1)))+&
             dery(nav%dcy,nav%v(nav%it(1)))+&
             derz(nav%dcz,nav%w(nav%it(1)))
    ref=norme2(mpid,nav%aux)
    nav%aux=derx(nav%dcx,nav%u(nav%it(1)))+&
            dery(nav%dcy,nav%v(nav%it(1)))+&
            derz(nav%dcz,nav%w(nav%it(1)))-&
            derx(nav%dcx,nav%sub_u)-&
            dery(nav%dcy,nav%sub_v)-&
            derz(nav%dcz,nav%sub_w)

    error=norme2(mpid,nav%aux)/ref
    if (mpid%rank==0) print*,'conv Div V       : ',error


    nav%aux%f=sqrt(nav%u(nav%it(1))%f**2&
                 + nav%v(nav%it(1))%f**2&
                 + nav%w(nav%it(1))%f**2)
    ref=norme2(mpid,nav%aux)

    nav%aux%f=sqrt((nav%sub_u%f-nav%u(nav%it(1))%f)**2&
                 + (nav%sub_v%f-nav%v(nav%it(1))%f)**2&
                 + (nav%sub_w%f-nav%w(nav%it(1))%f)**2)
    error=norme2(mpid,nav%aux)/ref

    if (mpid%rank==0) print*,'conv tot V       : ',error

    nav%aux%f=1._rk  ;    ref=integrale(mpid,nav%aux)
    nav%aux%f=nav%p(nav%it(1))%f - nav%sub_p%f
    call navier_nullify_boundary(mpid,nav,nav%aux,0)
    errort=integrale(mpid,nav%aux)
    nav%sub_p%f=nav%sub_p%f+errort/ref
    nav%aux%f=nav%sub_p%f
    ref=norme2(mpid,nav%aux)

    nav%aux%f=nav%p(nav%it(1))%f - nav%sub_p%f
    errort=norme2(mpid,nav%aux)/ref
    if (mpid%rank==0) print*,'conv tot P       : ',errort
    if (error<1d-9.and.errort<1d-9)  exit subit

endif testconv

nav%sub_u=nav%u(nav%it(1))
nav%sub_v=nav%v(nav%it(1))
nav%sub_w=nav%w(nav%it(1))
nav%sub_p=nav%p(nav%it(1))

     enddo subit

     !-> switch it
     iaux=nav%it(1)
     do i=1,nav%nt-1
       nav%it(i)=nav%it(i+1)
     enddo
     nav%it(nt)=iaux

     !---------------------------------------------------------------------
     !-> check solution

     t=nav%time
     do k=1,nav%nz
        do j=1,nav%ny
           do i=1,nav%nx
             x=nav%gridx%grid1d(i)
             y=nav%gridy%grid1d(j)
             z=nav%gridz%grid1d(k)
             uex(i,j,k,1)=sol(x,y,z,t,'u',nav%rey)
             uex(i,j,k,2)=sol(x,y,z,t,'v',nav%rey)
             uex(i,j,k,3)=sol(x,y,z,t,'w',nav%rey)
             pex(i,j,k)=sol(x,y,z,t,'p',nav%rey)
           enddo
        enddo
     enddo
     
 
     nav%aux%f=1._rk
     ref=norme2(mpid,nav%aux)

     nav%aux%f=0._rk
     nav%aux=derx(nav%dcx,nav%u(nav%it(nav%nt)))+&
          dery(nav%dcy,nav%v(nav%it(nav%nt)))+&
          derz(nav%dcz,nav%w(nav%it(nav%nt)))
    error=norme2(mpid,nav%aux)/ref
    if (mpid%rank==0) print*,'error Div V       : ',error

!     nav%aux=derx(nav%dcx,nav%u(nav%it(nav%nt)))+&
!          dery(nav%dcy,nav%v(nav%it(nav%nt)))+&
!          derz(nav%dcz,nav%w(nav%it(nav%nt)))
!    call navier_nullify_boundary(mpid,nav,nav%aux,1)

!    error=norme2(mpid,nav%aux)/ref
!    if (mpid%rank==0) print*,'error Div V   HI  : ',error

!     nav%aux=derx(nav%dcx,nav%u(nav%it(nav%nt)))+&
!          dery(nav%dcy,nav%v(nav%it(nav%nt)))+&
!          derz(nav%dcz,nav%w(nav%it(nav%nt)))
!    call navier_nullify_boundary(mpid,nav,nav%aux,-1)

!    error=norme2(mpid,nav%aux)/ref
!    if (mpid%rank==0) print*,'error Div V   HB  : ',error

!     nav%aux=derx(nav%dcx,nav%u(nav%it(nav%nt)))+&
!          dery(nav%dcy,nav%v(nav%it(nav%nt)))+&
!          derz(nav%dcz,nav%w(nav%it(nav%nt)))
!    call navier_nullify_boundary(mpid,nav,nav%aux,0)

!    error=norme2(mpid,nav%aux)/ref
!    if (mpid%rank==0) print*,'error Div V   HBI : ',error

    vectorerror(:,:,:,5)=nav%aux%f


    nav%aux%f=sqrt(uex(:,:,:,1)**2 &
                 + uex(:,:,:,2)**2 &
                 + uex(:,:,:,3)**2)
    ref=norme2(mpid,nav%aux)

    nav%aux%f=sqrt((uex(:,:,:,1)-nav%u(nav%it(nav%nt))%f)**2&
                 + (uex(:,:,:,2)-nav%v(nav%it(nav%nt))%f)**2&
                 + (uex(:,:,:,3)-nav%w(nav%it(nav%nt))%f)**2)

    error=norme2(mpid,nav%aux)/ref
    if (mpid%rank==0) print*,'error tot V       : ',error

!    nav%aux%f=sqrt((uex(:,:,:,1)-nav%u(nav%it(nav%nt))%f)**2&
!                 + (uex(:,:,:,2)-nav%v(nav%it(nav%nt))%f)**2&
!                 + (uex(:,:,:,3)-nav%w(nav%it(nav%nt))%f)**2)
!    call navier_nullify_boundary(mpid,nav,nav%aux,1)
!    error=norme2(mpid,nav%aux)/ref
!    if (mpid%rank==0) print*,'error tot V   HI  : ',error

!    nav%aux%f=sqrt((uex(:,:,:,1)-nav%u(nav%it(nav%nt))%f)**2&
!                 + (uex(:,:,:,2)-nav%v(nav%it(nav%nt))%f)**2&
!                 + (uex(:,:,:,3)-nav%w(nav%it(nav%nt))%f)**2)
!    call navier_nullify_boundary(mpid,nav,nav%aux,-1)
!    error=norme2(mpid,nav%aux)/ref
!    if (mpid%rank==0) print*,'error tot V   HB  : ',error

!    nav%aux%f=sqrt((uex(:,:,:,1)-nav%u(nav%it(nav%nt))%f)**2&
!                 + (uex(:,:,:,2)-nav%v(nav%it(nav%nt))%f)**2&
!                 + (uex(:,:,:,3)-nav%w(nav%it(nav%nt))%f)**2)
!    call navier_nullify_boundary(mpid,nav,nav%aux,0)
!    error=norme2(mpid,nav%aux)/ref
!    if (mpid%rank==0) print*,'error tot V   HBI : ',error


    nav%aux%f=1._rk  ;    ref=integrale(mpid,nav%aux)
    nav%aux%f=nav%p(nav%it(nav%nt))%f - pex
    call navier_nullify_boundary(mpid,nav,nav%aux,0)
    error=integrale(mpid,nav%aux)
    pex=pex+error/ref
    nav%aux%f=pex
    ref=norme2(mpid,nav%aux)

    nav%aux%f=nav%p(nav%it(nav%nt))%f - pex
    error=norme2(mpid,nav%aux)/ref
    if (mpid%rank==0) print*,'error tot P       : ',error

!    nav%aux%f=nav%p(nav%it(nav%nt))%f - pex
!    call navier_nullify_boundary(mpid,nav,nav%aux,1)
!    error=norme2(mpid,nav%aux)/ref
!    if (mpid%rank==0) print*,'error tot P   HI  : ',error

!    nav%aux%f=nav%p(nav%it(nav%nt))%f - pex
!    call navier_nullify_boundary(mpid,nav,nav%aux,-1)
!    error=norme2(mpid,nav%aux)/ref
!    if (mpid%rank==0) print*,'error tot P   HB  : ',error

!    nav%aux%f=nav%p(nav%it(nav%nt))%f - pex
!    call navier_nullify_boundary(mpid,nav,nav%aux,0)
!    error=norme2(mpid,nav%aux)/ref
!    if (mpid%rank==0) print*,'error tot P   HBI : ',error


    nav%aux%f=1._rk ;     reft=integrale(mpid,nav%aux)
    errort=0.5_rk*(norme2(mpid,nav%u(nav%it(nav%nt)))**2 &
                  +norme2(mpid,nav%v(nav%it(nav%nt)))**2 &
                  +norme2(mpid,nav%w(nav%it(nav%nt))))
    if (mpid%rank==0) print*,'En Cinet  V       : ',errort/reft

    errort=norme2(mpid,nav%u(nav%it(nav%nt))-nav%u(nav%it(nav%nt-1)))**2 &
          +norme2(mpid,nav%v(nav%it(nav%nt))-nav%v(nav%it(nav%nt-1)))**2 &
          +norme2(mpid,nav%w(nav%it(nav%nt))-nav%w(nav%it(nav%nt-1)))
    if (mpid%rank==0) print*,'Station   V       : ',sqrt(errort)/(reft)

  if(ite>=10.and.sqrt(errort)/(reft)<1d-6) exit temps

  enddo temps
  call system_clock(t2,irate)
  time=real(t2-t1)/real(irate)
  if (mpid%rank==0) print*,'time : ',time,time/(ite-20)

  !------------------------------------------------------------------------ 
  !-> time loop end
  !------------------------------------------------------------------------ 

    nav%aux%f=0._rk
    nav%aux=derx(nav%dcx,nav%phi(nav%it(nav%nt)))

!  goto 100
  k=nav%nz-1
  do j=1,nav%ny
     do i=1,nav%nx
!        write(10+mpid%rank,*)nav%gridx%grid1d(i),nav%gridy%grid1d(j),&
!             nav%v(nav%it(nav%nt))%f(i,j,k),nav%p(nav%it(nav%nt))%f(i,j,k),&
!             uex(i,j,k,1),nav%aux%f(i,j,k),pex(i,j,k)
        write(10+mpid%rank,'(20es17.8)')nav%gridx%grid1d(i),nav%gridy%grid1d(j),&
             nav%u(nav%it(nav%nt))%f(i,j,k),nav%v(nav%it(nav%nt))%f(i,j,k),&
             nav%w(nav%it(nav%nt))%f(i,j,k),nav%p(nav%it(nav%nt))%f(i,j,k),&
!             nav%w(nav%it(nav%nt))%f(i,j,k),nav%phi(nav%it(nav%nt))%f(i,j,k),&
             nav%aux%f(i,j,k),pex(i,j,k),&
             uex(i,j,k,1),uex(i,j,k,2),uex(i,j,k,3)
     enddo
     write(10+mpid%rank,*)
  enddo
  close(10+mpid%rank)
!100 continue
if (.true.) then

 vectorerror(:,:,:,1)=nav%u(nav%it(nav%nt))%f-uex(:,:,:,1)
 vectorerror(:,:,:,2)=nav%v(nav%it(nav%nt))%f-uex(:,:,:,2)
 vectorerror(:,:,:,3)=nav%w(nav%it(nav%nt))%f-uex(:,:,:,3)
 vectorerror(:,:,:,4)=nav%p(nav%it(nav%nt))%f-pex
 !vectorerror(:,:,:,1:3)=uex(:,:,:,1:3)
 !vectorerror(:,:,:,4)=pex
!    nav%aux%f=0._rk
!    nav%aux=derx(nav%dcx,nav%p(nav%it(nav%nt)))
! vectorerror(:,:,:,4)=nav%aux%f
!    nav%aux%f=0._rk
!    nav%aux=derx(nav%dcx,nav%phi(nav%it(nav%nt)))
! vectorerror(:,:,:,5)=nav%aux%f

  do k=1,5
    nav%aux%f=vectorerror(:,:,:,k)
    call field_zero_edges(nav%aux)
    vectorerror(:,:,:,k)=nav%aux%f
  enddo

  !k=((nav%nz-2)/2) + 2
  k=nav%nz-1
  do j=1,nav%ny
     do i=1,nav%nx
        write(20+mpid%rank,'(20es17.8)')nav%gridx%grid1d(i),nav%gridy%grid1d(j),&
!             nav%gridz%grid1d(k),&
             vectorerror(i,j,k,1),&
             vectorerror(i,j,k,2),&
             vectorerror(i,j,k,3),&
             vectorerror(i,j,k,4),&
             vectorerror(i,j,k,5)
     enddo
     write(20+mpid%rank,*)
  enddo
  close(20+mpid%rank)
endif


  call write_field('vel_u',nav%u(nav%it(nav%nt)),mpid)
  call write_field('vel_v',nav%v(nav%it(nav%nt)),mpid)
  call write_field('vel_w',nav%w(nav%it(nav%nt)),mpid)
  call write_field('vel_p',nav%p(nav%it(nav%nt)),mpid)
  call write_field('vel_phi',nav%phi(nav%it(nav%nt)),mpid)


  !------------------------------------------------------------------------ 
  !-> post-computation
  !------------------------------------------------------------------------ 

  call navier_finalization(cmd,mpid,nav)


contains

function integrale(mpid,x)
  use class_field
  use class_md
  use precision
  implicit none
  type(field),intent(in) ::x
  type(mpi_data) :: mpid
  real(rk) :: integrale1,integrale
  integer(ik) :: i,j,k

  integrale1=0._rk
  do k=2,x%nz-1
     do j=2,x%ny-1
        do i=2,x%nx-1
           integrale1=integrale1+x%f(i,j,k)
        enddo
     enddo
  enddo

  !-> x boundary
  integrale1=integrale1+sum(x%f(1,2:x%ny-1,2:x%nz-1))
  integrale1=integrale1+sum(x%f(x%nx,2:x%ny-1,2:x%nz-1))

  !-> y boundary
  integrale1=integrale1+sum(x%f(2:x%nx-1,1,2:x%nz-1))
  integrale1=integrale1+sum(x%f(2:x%nx-1,x%ny,2:x%nz-1))

  !-> z boundary
  integrale1=integrale1+sum(x%f(2:x%nx-1,2:x%ny-1,1))
  integrale1=integrale1+sum(x%f(2:x%nx-1,2:x%ny-1,x%nz))

  call md_mpi_reduce_double(mpid,integrale1,integrale)
call md_mpi_bcast_double(mpid,integrale,0)
end function integrale


function norme2(mpid,x)
  use class_field
  use class_md
  use precision
  implicit none
  type(field),intent(in) ::x
  type(mpi_data) :: mpid
  real(rk) :: norme2,som1
  integer(ik) :: i,j,k

  som1=0._rk
  do k=2,x%nz-1
     do j=2,x%ny-1
        do i=2,x%nx-1
           som1=som1+(x%f(i,j,k))**2
        enddo
     enddo
  enddo

  !-> x boundary
  som1=som1+sum((x%f(1,2:x%ny-1,2:x%nz-1))**2)
  som1=som1+sum((x%f(x%nx,2:x%ny-1,2:x%nz-1))**2)

  !-> y boundary
  som1=som1+sum((x%f(2:x%nx-1,1,2:x%nz-1))**2)
  som1=som1+sum((x%f(2:x%nx-1,x%ny,2:x%nz-1))**2)

  !-> z boundary
  som1=som1+sum((x%f(2:x%nx-1,2:x%ny-1,1))**2)
  som1=som1+sum((x%f(2:x%nx-1,2:x%ny-1,x%nz))**2)


  call md_mpi_reduce_double(mpid,som1,norme2)
  call md_mpi_bcast_double(mpid,norme2,0)

  norme2=sqrt(norme2)

end function norme2



end program testnavier3d


subroutine error_stop(error_mesg)
!  use mpi_utils, only : code,rang
  implicit none
  character(*) :: error_mesg
!  call MPI_FINALIZE(code)
!  if (rang==0) then
     print'(a)',error_mesg(1:len_trim(error_mesg))
!  endif
!  stop
  
end subroutine error_stop

