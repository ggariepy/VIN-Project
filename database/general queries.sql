--select * from VEHICLE where display_vehicle = 1 and body_style like '%crew%' and engine like '%5.7%' order by Asking_Price asc
--select * from VEHICLE where change_date_description like '%Disappeared%'
/*select 
       Asking_Price, 
       Advertised_Mileage, 
       Body_Style, 
       Engine, 
       Change_Date_Description, 
       VIN, 
       Dealer_URL, 
       Carfax_URL 
from 
     VEHICLE      
where 
      VIN = '1D7RV1CT2BS516927'            
      and Display_Vehicle = 1
*/

select 
       Asking_Price, 
       Advertised_Mileage, 
       Body_Style, 
       Engine, 
       Change_Date_Description, 
       VIN, 
       Dealer_URL, 
       Carfax_URL 
from 
     VEHICLE 
where 
      display_vehicle = 1 and 
      body_style like '%crew%' and 
      engine like '%5.7%' and      
      asking_price < 24000
      order by Asking_Price asc, Advertised_Mileage asc


