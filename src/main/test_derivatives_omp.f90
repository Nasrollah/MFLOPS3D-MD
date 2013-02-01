program test_derivatives_omp
  !  use parameters
!$ use OMP_LIB
  use class_field
  use class_mesh
  use class_derivatives
  use color_print
  use command_line
  implicit none

  integer(ik),parameter :: nt=1
  integer(ik) :: nx,ny,nz
  type(derivatives_coefficients) :: dcx,dcy,dcz
  type(mesh_grid) :: gridx,gridy,gridz
  type(field) :: u(nt)
  type(field) :: dxu,ddxu,dyu,ddyu,dzu,ddzu
  type(cmd_line) :: cmd

  integer(ik) :: i,j,k,l,m
  real(rk) :: r,p
  real(rk),allocatable :: x(:),y(:),z(:)
  real(rk),allocatable :: tmpx(:),tmpy(:),tmpz(:)
  real(rk),allocatable :: uex(:,:,:,:),uey(:,:,:,:),uez(:,:,:,:)
  real(rk) :: xa,xb,pi,alp,bet,derror,dderror,test
  real(rk) :: sumderr,sumdderr,derror1,dderror1,errcoef=2._rk
  character(5) :: out 
  integer(ik) :: mindim=192,maxdim=4050,nerr
  integer(8) :: t1,t2,irate

  !-> get command line informations
  call commandline(cmd)

  ! define level of output files : LOW or FULL
  out='FULL'

  !-> initial dimensions
  nx=cmd%nx ; ny=cmd%ny ; nz=cmd%nz
  sumderr=0._rk ; sumdderr=0._rk ; nerr=0
  
  !-> initialize work array
  allocate(x(nx),y(ny),z(nz))
  allocate(tmpx(nx),tmpy(ny),tmpz(nz))
  allocate(uex(nx,ny,nz,2),uey(nx,ny,nz,2),uez(nx,ny,nz,2))

  !-> initialize type field
  call field_init(u(1),"U",nx,ny,nz)
  call field_init(dxu,"DXU",nx,ny,nz)
  call field_init(ddxu,"DDXU",nx,ny,nz)
  call field_init(dyu,"DYU",nx,ny,nz)
  call field_init(ddyu,"DDYU",nx,ny,nz)
  call field_init(dzu,"DZU",nx,ny,nz)
  call field_init(ddzu,"DDZU",nx,ny,nz)

  !-> initialize grid
  call mesh_init(gridx,'gridx','x',nx,1,1)
  call mesh_init(gridy,'gridy','y',nx,ny,1)
  call mesh_init(gridz,'gridz','z',1,1,nz)
  
  !-> define grid
  call mesh_grid_init(gridx,'x',nx,1,1)
  call mesh_grid_init(gridy,'y',nx,ny,1)
  call mesh_grid_init(gridz,'z',1,1,nz)

  !-> define exact solution and derivatives
  alp=1._rk ; bet=2._rk
  pi=4._rk*atan(1._rk)

  x=gridx%grid1d ; y=gridy%grid1d ; z=gridz%grid1d

!$OMP PARALLEL 
!$OMP DO PRIVATE(k) SCHEDULE(RUNTIME)
  do k=1,u(1)%nz
     do j=1,u(1)%ny
        do i=1,u(1)%nx
           !-> grid
           !x(i)=gridx%grid1d(i) ; y(j)=gridy%grid1d(j) ; z(k)=gridz%grid1d(k)
           !-> test function
           u(1)%f(i,j,k)=&
                sin(2._rk*pi*alp*x(i))+cos(2._rk*pi*bet*x(i))+ &
                sin(2._rk*pi*alp*y(j))+cos(2._rk*pi*bet*y(j))+ &
                sin(2._rk*pi*alp*z(k))+cos(2._rk*pi*bet*z(k))                
           !-> first derivative of test function
           uex(i,j,k,1)=2._rk*pi*(alp*cos(2._rk*pi*alp*x(i)) &
                -bet*sin(2._rk*pi*bet*x(i)))
           uey(i,j,k,1)=2._rk*pi*(alp*cos(2._rk*pi*alp*y(j)) &
                -bet*sin(2._rk*pi*bet*y(j)))
           uez(i,j,k,1)=2._rk*pi*(alp*cos(2._rk*pi*alp*z(k)) &
                -bet*sin(2._rk*pi*bet*z(k)))
           !-> second derivative of test function
           uex(i,j,k,2)=4._rk*pi*pi*(-alp*alp*sin(2._rk*pi*alp*x(i)) &
                -bet*bet*cos(2._rk*pi*bet*x(i)))
           uey(i,j,k,2)=4._rk*pi*pi*(-alp*alp*sin(2._rk*pi*alp*y(j)) &
                -bet*bet*cos(2._rk*pi*bet*y(j)))
           uez(i,j,k,2)=4._rk*pi*pi*(-alp*alp*sin(2._rk*pi*alp*z(k)) &
                -bet*bet*cos(2._rk*pi*bet*z(k)))
        enddo
     enddo
  enddo
!$OMP END DO
!$OMP END PARALLEL

  !-> initialisation of derivatives coefficients
  !call derivatives_coefficients_init(gridx,dcx,nx)
  !call derivatives_coefficients_init(gridy,dcy,ny)
  !call derivatives_coefficients_init(gridz,dcz,nz)
  call derivatives_coefficients_init(gridx,dcx,nx,solver='yes')
  call derivatives_coefficients_init(gridy,dcy,ny,solver='yes')
  call derivatives_coefficients_init(gridz,dcz,nz,solver='yes')

  !-> computation of derivatives 
  call system_clock(t1,irate)
  dxu=derx(dcx,u(1)) ; ddxu=dderx(dcx,u(1))
  dyu=dery(dcy,u(1)) ; ddyu=ddery(dcy,u(1))
  dzu=derz(dcz,u(1)) ; ddzu=dderz(dcz,u(1))
  call system_clock(t2,irate)
  !        dxu=u(1)%derx(dcx) ; ddxu=u(1)%dderx(dcx)

  print*,'time',real(t2-t1)/real(irate)

  !-> compute errors
  
  call err(dcx,dxu%f,uex(1,1,1,1),nx,ny,nz,derror)
  call err(dcx,ddxu%f,uex(1,1,1,2),nx,ny,nz,dderror)
  write(*,'(a,f8.2,a,3(a,i6),3(a,es9.2))')'Memory usage: ', &
       nx*ny*nz*8._rk*7._rk/(1024._rk*1024._rk),' Mb, ', &
       'Dimensions : ',nx,' x ',ny,' x ',nz, &
       ', pasx=',gridx%pas,', dx error=',derror,', ddx error=',dderror
  write(300,'(15es17.8)')real(nx),gridx%pas,derror,dderror
  
  call err(dcy,dyu%f,uey(1,1,1,1),nx,ny,nz,derror)
  call err(dcy,ddyu%f,uey(1,1,1,2),nx,ny,nz,dderror)
  write(*,'(a,f8.2,a,3(a,i6),3(a,es9.2))')'Memory usage: ', &
       nx*ny*nz*8._rk*7._rk/(1024._rk*1024._rk),' Mb, ', &
       'Dimensions : ',nx,' x ',ny,' x ',nz, & 
       ', pasy=',gridy%pas,', dy error=',derror,', ddy error=',dderror
  write(301,'(15es17.8)')real(ny),gridy%pas,derror,dderror
  
  call err(dcz,dzu%f,uez(1,1,1,1),nx,ny,nz,derror)
  call err(dcz,ddzu%f,uez(1,1,1,2),nx,ny,nz,dderror)
  write(*,'(a,f8.2,a,3(a,i6),3(a,es9.2))')'Memory usage: ', &
       nx*ny*nz*8._rk*7._rk/(1024._rk*1024._rk),' Mb, ', &
       'Dimensions : ',nx,' x ',ny,' x ',nz, & 
       ', pasz=',gridz%pas,', dz error=',derror,', ddz error=',dderror
  write(302,'(15es17.8)')real(nz),gridz%pas,derror,dderror
  
  !-> write results
  if (out=='FULL') then
     do j=1,ny
        do i=1,nx
        write(120,'(14e17.8)')x(i),y(j),ddxu%f(i,j,1),uex(i,j,1,2),&
             ddxu%f(i,j,2),uex(i,j,2,2)
        enddo
        write(120,*)
     enddo

     do i=1,nx
        write(100,'(14e17.8)')x(i),u(1)%f(i,1,1),&
             dxu%f(i,1,1),uex(i,1,1,1),abs(uex(i,1,1,1)-dxu%f(i,1,1)), &
             ddxu%f(i,1,1),uex(i,1,1,2),abs(uex(i,1,1,2)-ddxu%f(i,1,1))
     enddo
     do i=1,nx
        write(110,'(14e17.8)')x(i),u(1)%f(i,1,2),&
             dxu%f(i,1,2),uex(i,1,2,1),abs(uex(i,1,2,1)-dxu%f(i,1,2)), &
             ddxu%f(i,1,2),uex(i,1,2,2),abs(uex(i,1,2,2)-ddxu%f(i,1,2))
     enddo
     do j=1,ny
        write(101,'(14e17.8)')y(j),u(1)%f(1,j,1),&
             dyu%f(1,j,1),uey(1,j,1,1),abs(uey(1,j,1,1)-dyu%f(1,j,1)), &
             ddyu%f(1,j,1),uey(1,j,1,2),abs(uey(1,j,1,2)-ddyu%f(1,j,1))
     enddo
     do k=1,nz
        write(102,'(14e17.8)')z(k),u(1)%f(1,1,k),&
             dzu%f(1,1,k),uez(1,1,k,1),abs(uez(1,1,k,1)-dzu%f(1,1,k)), &
             ddzu%f(1,1,k),uez(1,1,k,2),abs(uez(1,1,k,2)-ddzu%f(1,1,k))
     enddo
     do i=1,nx-1
        write(200,'(10e24.13)')x(i),x(i+1)-x(i) 
     enddo
  endif

  !-> deallocate work arrays
  deallocate(x,y,z)
  deallocate(tmpx,tmpy,tmpz)
  deallocate(uex,uey,uez)

  !-> deallocate tyep field
  call field_destroy(u(1))
  call field_destroy(dxu)
  call field_destroy(ddxu)
  call field_destroy(dyu)
  call field_destroy(ddyu)
  call field_destroy(dzu)
  call field_destroy(ddzu)

end program test_derivatives_omp

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

subroutine err(dc,u,uex,nx,ny,nz,error)
  use class_derivatives
  use precision
  implicit none
  type(derivatives_coefficients),intent(in) :: dc
  integer(ik) :: nx,ny,nz,i,j,k
  real(rk) :: u(nx,ny,nz),uex(nx,ny,nz)
  real(rk) :: som1,som2,error
  
  
  if (dertype(dc)) then
  
     som1=0._rk
     som2=0._rk
     do k=2,nz-1
        do j=2,ny-1
           do i=2,nx-1
              som1=som1+(u(i,j,k)-uex(i,j,k))**2
              som2=som2+uex(i,j,k)**2
           enddo
        enddo
     enddo
     !-> x boundary
     som1=som1+sum((u(1,2:ny-1,2:nz-1)-uex(1,2:ny-1,2:nz-1))**2)
     som2=som2+sum(uex(1,2:ny-1,2:nz-1)**2)
     som1=som1+sum((u(nx,2:ny-1,2:nz-1)-uex(nx,2:ny-1,2:nz-1))**2)
     som2=som2+sum(uex(nx,2:ny-1,2:nz-1)**2)

     !-> y boundary
     som1=som1+sum((u(2:nx-1,1,2:nz-1)-uex(2:nx-1,1,2:nz-1))**2)
     som2=som2+sum(uex(2:nx-1,1,2:nz-1)**2)
     som1=som1+sum((u(2:nx-1,ny,2:nz-1)-uex(2:nx-1,ny,2:nz-1))**2)
     som2=som2+sum(uex(2:nx-1,ny,2:nz-1)**2)

     !-> z boundary
     som1=som1+sum((u(2:nx-1,2:ny-1,1)-uex(2:nx-1,2:ny-1,1))**2)
     som2=som2+sum(uex(2:nx-1,2:nz-1,1)**2)
     som1=som1+sum((u(2:nx-1,2:ny-1,nz)-uex(2:nx-1,2:ny-1,nz))**2)
     som2=som2+sum(uex(2:nx-1,2:ny-1,nz)**2)


     error=sqrt(som1)/sqrt(som2)
     !error=sqrt(som1/(nx*ny*nz))

else

   som1=0._rk
   som2=0._rk
   do k=1,nz
      do j=1,ny
         do i=1,nx
            som1=som1+(u(i,j,k)-uex(i,j,k))**2
            som2=som2+uex(i,j,k)**2
         enddo
      enddo
   enddo
   error=sqrt(som1)/sqrt(som2)
   !error=sqrt(som1/(nx*ny*nz))

endif
end subroutine err
