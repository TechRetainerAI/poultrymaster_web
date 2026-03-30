/****** Script for SelectTopNRows command from SSMS  ******/
TRUNCATE TABLE [Crypto].[dbo].[tblEthTransaction]

ALTER TABLE [Crypto].[dbo].[tblEthTransaction]
ADD Type varchar(255) null


TRUNCATE TABLE [Crypto].[dbo].[tblBnbTransaction]

ALTER TABLE [Crypto].[dbo].[tblBnbTransaction]
ADD Type varchar(255) null 


select * from [Crypto].[dbo].[tblEthTransaction]
where ToAddress  in (
SELECT [FromAddress] FROM [Crypto].[dbo].[tblEthTransaction]
where ToAddress = '0x45ecd328179d61c4f74ce729c2399675e5bc85d0' and FromAddress <> '0x45ecd328179d61c4f74ce729c2399675e5bc85d0')

-- 65,000 half - 1.3 Million 
-- *************************
-- UK, someone with school admission marries and goes with husband
-- Accompanying person gets 5 years of work permit
-- As soon as the connection comes up, he calls you.if he gets a woman, he will call a man, if he gets a man he will call a woman
-- If you delay he will call someone else. He will keep calling you and warning you to prepare yourself. Because he will not delay when 
-- When the opportunity comes! make your 

-- Sold motor, goats, sheeps n all to make the 650
-- Second payment that Frederick 

-- WHEN YOU APPLY, TO THE COMPANY FOR THE JOB, THEY GIVE YOU A COS --
-- YOU THEN USE THAT TO APPLY FOR THE VISA
-- THE PERSON IS NOT A NURSE.
-- 9500 POUNDS (DEPENDENT)  1.3 mill
-- SHE PAID 8000 POUNDS 
-- SHE WILL DO AN EXAM BEFORE STARTING WORK
-- SHE DID THE EXAM and the interview
-- Clinton only medicals and marriage

-- HE SAID COS IS 10,000. SO he took 5000 from both parties and then applied for the job.
-- For the care, after UNIVERSITY, you can apply using the english proficiency
-- After university, you get the proficiency letter. so need to write any exams. without university, you 
-- will have to write it.

