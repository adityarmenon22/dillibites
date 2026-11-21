-- =====================================================================
--  DilliBites : APPLICATION DATABASE & DATA WAREHOUSE SETUP
--  Target: MySQL 8.0+ (Workbench & setup_db.py compatible)
-- =====================================================================

SET SQL_SAFE_UPDATES = 0;

-- #####################################################################
-- ##  PART 1 : OPERATIONAL SCHEMA (DDL)
-- #####################################################################

DROP DATABASE IF EXISTS dillibites;
CREATE DATABASE dillibites CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE dillibites;

CREATE TABLE areas (
    area_id    INT AUTO_INCREMENT PRIMARY KEY,
    area_name  VARCHAR(60) NOT NULL,
    city       VARCHAR(40) NOT NULL,
    pincode    CHAR(6)     NOT NULL,
    CONSTRAINT uq_area UNIQUE (area_name, city),
    CONSTRAINT chk_pincode CHECK (pincode REGEXP '^[0-9]{6}$')
);

CREATE TABLE menu_categories (
    category_id   INT AUTO_INCREMENT PRIMARY KEY,
    category_name VARCHAR(40) NOT NULL UNIQUE
);

CREATE TABLE users (
    user_id        INT AUTO_INCREMENT PRIMARY KEY,
    full_name      VARCHAR(80)  NOT NULL,
    email          VARCHAR(100) NOT NULL,
    phone          CHAR(10)     NOT NULL,
    password_hash  VARCHAR(100) NOT NULL,
    user_type      ENUM('CUSTOMER','PARTNER','OWNER') NOT NULL,
    created_at     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_users_email UNIQUE (email),
    CONSTRAINT uq_users_phone UNIQUE (phone),
    CONSTRAINT chk_users_phone CHECK (phone REGEXP '^[6-9][0-9]{9}$')
);

CREATE TABLE customers (
    customer_id     INT PRIMARY KEY,
    wallet_balance  DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    loyalty_points  INT           NOT NULL DEFAULT 0,
    CONSTRAINT fk_cust_user FOREIGN KEY (customer_id)
        REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT chk_wallet CHECK (wallet_balance >= 0),
    CONSTRAINT chk_points CHECK (loyalty_points >= 0)
);

CREATE TABLE delivery_partners (
    partner_id    INT PRIMARY KEY,
    vehicle_type  ENUM('BIKE','SCOOTER','CYCLE') NOT NULL,
    vehicle_no    VARCHAR(15) NOT NULL,
    is_available  BOOLEAN NOT NULL DEFAULT TRUE,
    joined_on     DATE NOT NULL,
    CONSTRAINT fk_partner_user FOREIGN KEY (partner_id)
        REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT uq_vehicle UNIQUE (vehicle_no)
);

CREATE TABLE restaurant_owners (
    owner_id  INT PRIMARY KEY,
    gst_no    CHAR(15) NOT NULL,
    CONSTRAINT fk_owner_user FOREIGN KEY (owner_id)
        REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT uq_gst UNIQUE (gst_no)
);

CREATE TABLE addresses (
    address_id    INT AUTO_INCREMENT PRIMARY KEY,
    customer_id   INT NOT NULL,
    area_id       INT NOT NULL,
    address_line  VARCHAR(150) NOT NULL,
    label         ENUM('HOME','HOSTEL','WORK','OTHER') NOT NULL DEFAULT 'HOME',
    CONSTRAINT fk_addr_cust FOREIGN KEY (customer_id)
        REFERENCES customers(customer_id) ON DELETE CASCADE,
    CONSTRAINT fk_addr_area FOREIGN KEY (area_id)
        REFERENCES areas(area_id)
);

CREATE TABLE restaurants (
    restaurant_id  INT AUTO_INCREMENT PRIMARY KEY,
    owner_id       INT NOT NULL,
    area_id        INT NOT NULL,
    name           VARCHAR(80) NOT NULL,
    cuisine        VARCHAR(40) NOT NULL,
    opens_at       TIME NOT NULL,
    closes_at      TIME NOT NULL,
    is_active      BOOLEAN NOT NULL DEFAULT TRUE,
    created_at     DATE NOT NULL,
    serves_after_midnight BOOLEAN GENERATED ALWAYS AS (closes_at < opens_at) STORED,
    CONSTRAINT uq_rest_name UNIQUE (name),
    CONSTRAINT fk_rest_owner FOREIGN KEY (owner_id) REFERENCES restaurant_owners(owner_id),
    CONSTRAINT fk_rest_area  FOREIGN KEY (area_id)  REFERENCES areas(area_id)
);

CREATE TABLE menu_items (
    item_id        INT AUTO_INCREMENT PRIMARY KEY,
    restaurant_id  INT NOT NULL,
    category_id    INT NOT NULL,
    item_name      VARCHAR(80)  NOT NULL,
    description    VARCHAR(200),
    price          DECIMAL(8,2) NOT NULL,
    is_veg         BOOLEAN NOT NULL,
    is_available   BOOLEAN NOT NULL DEFAULT TRUE,
    stock_qty      INT NULL,
    CONSTRAINT uq_item_per_rest UNIQUE (restaurant_id, item_name),
    CONSTRAINT fk_item_rest FOREIGN KEY (restaurant_id) REFERENCES restaurants(restaurant_id) ON DELETE CASCADE,
    CONSTRAINT fk_item_cat  FOREIGN KEY (category_id)   REFERENCES menu_categories(category_id),
    CONSTRAINT chk_price CHECK (price > 0),
    CONSTRAINT chk_stock CHECK (stock_qty IS NULL OR stock_qty >= 0)
);

CREATE TABLE coupons (
    coupon_id              INT AUTO_INCREMENT PRIMARY KEY,
    code                   VARCHAR(20) NOT NULL,
    discount_pct           TINYINT NOT NULL,
    max_discount           DECIMAL(8,2) NOT NULL,
    min_order_value        DECIMAL(8,2) NOT NULL DEFAULT 0,
    valid_from             DATE NOT NULL,
    valid_to               DATE NOT NULL,
    max_uses_per_customer  TINYINT NOT NULL DEFAULT 1,
    CONSTRAINT uq_coupon_code UNIQUE (code),
    CONSTRAINT chk_pct   CHECK (discount_pct BETWEEN 1 AND 100),
    CONSTRAINT chk_valid CHECK (valid_to >= valid_from)
);

CREATE TABLE orders (
    order_id       INT AUTO_INCREMENT PRIMARY KEY,
    customer_id    INT NOT NULL,
    restaurant_id  INT NOT NULL,
    address_id     INT NOT NULL,
    coupon_id      INT NULL,
    order_time     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status         ENUM('PLACED','PREPARING','OUT_FOR_DELIVERY','DELIVERED','CANCELLED')
                   NOT NULL DEFAULT 'PLACED',
    subtotal       DECIMAL(10,2) NOT NULL DEFAULT 0,
    discount_amt   DECIMAL(10,2) NOT NULL DEFAULT 0,
    delivery_fee   DECIMAL(10,2) NOT NULL DEFAULT 0,
    total_amt      DECIMAL(10,2) NOT NULL DEFAULT 0,
    CONSTRAINT fk_ord_cust   FOREIGN KEY (customer_id)   REFERENCES customers(customer_id),
    CONSTRAINT fk_ord_rest   FOREIGN KEY (restaurant_id) REFERENCES restaurants(restaurant_id),
    CONSTRAINT fk_ord_addr   FOREIGN KEY (address_id)    REFERENCES addresses(address_id),
    CONSTRAINT fk_ord_coupon FOREIGN KEY (coupon_id)     REFERENCES coupons(coupon_id),
    CONSTRAINT chk_ord_amounts CHECK (subtotal >= 0 AND discount_amt >= 0
                                      AND delivery_fee >= 0 AND total_amt >= 0)
);

CREATE TABLE order_items (
    order_id    INT NOT NULL,
    item_id     INT NOT NULL,
    quantity    TINYINT NOT NULL,
    unit_price  DECIMAL(8,2) NOT NULL,
    PRIMARY KEY (order_id, item_id),
    CONSTRAINT fk_oi_order FOREIGN KEY (order_id) REFERENCES orders(order_id) ON DELETE CASCADE,
    CONSTRAINT fk_oi_item  FOREIGN KEY (item_id)  REFERENCES menu_items(item_id),
    CONSTRAINT chk_qty CHECK (quantity BETWEEN 1 AND 20),
    CONSTRAINT chk_oi_price CHECK (unit_price > 0)
);

CREATE TABLE payments (
    payment_id  INT AUTO_INCREMENT PRIMARY KEY,
    order_id    INT NOT NULL,
    method      ENUM('UPI','CARD','COD','WALLET') NOT NULL,
    pay_status  ENUM('PENDING','PAID','FAILED','REFUNDED') NOT NULL DEFAULT 'PENDING',
    amount      DECIMAL(10,2) NOT NULL,
    paid_at     DATETIME NULL,
    CONSTRAINT uq_pay_order UNIQUE (order_id),
    CONSTRAINT fk_pay_order FOREIGN KEY (order_id) REFERENCES orders(order_id) ON DELETE CASCADE,
    CONSTRAINT chk_pay_amt CHECK (amount >= 0)
);

CREATE TABLE deliveries (
    delivery_id   INT AUTO_INCREMENT PRIMARY KEY,
    order_id      INT NOT NULL,
    partner_id    INT NOT NULL,
    picked_at     DATETIME NOT NULL,
    delivered_at  DATETIME NULL,
    distance_km   DECIMAL(4,1) NOT NULL,
    CONSTRAINT uq_del_order UNIQUE (order_id),
    CONSTRAINT fk_del_order   FOREIGN KEY (order_id)   REFERENCES orders(order_id) ON DELETE CASCADE,
    CONSTRAINT fk_del_partner FOREIGN KEY (partner_id) REFERENCES delivery_partners(partner_id),
    CONSTRAINT chk_del_time CHECK (delivered_at IS NULL OR delivered_at > picked_at),
    CONSTRAINT chk_distance CHECK (distance_km > 0)
);

CREATE TABLE reviews (
    review_id          INT AUTO_INCREMENT PRIMARY KEY,
    order_id           INT NOT NULL,
    restaurant_rating  TINYINT NOT NULL,
    delivery_rating    TINYINT NULL,
    comment            VARCHAR(200),
    reviewed_at        DATETIME NOT NULL,
    CONSTRAINT uq_review_order UNIQUE (order_id),
    CONSTRAINT fk_rev_order FOREIGN KEY (order_id) REFERENCES orders(order_id) ON DELETE CASCADE,
    CONSTRAINT chk_rrating CHECK (restaurant_rating BETWEEN 1 AND 5),
    CONSTRAINT chk_drating CHECK (delivery_rating IS NULL OR delivery_rating BETWEEN 1 AND 5)
);

CREATE TABLE order_status_log (
    log_id      INT AUTO_INCREMENT PRIMARY KEY,
    order_id    INT NOT NULL,
    old_status  VARCHAR(20) NOT NULL,
    new_status  VARCHAR(20) NOT NULL,
    changed_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_log_order FOREIGN KEY (order_id) REFERENCES orders(order_id) ON DELETE CASCADE
);

CREATE TABLE app_settings (
    setting_key    VARCHAR(40) PRIMARY KEY,
    setting_value  VARCHAR(40) NOT NULL
);
INSERT INTO app_settings VALUES ('is_raining', '0'), ('rain_surge_fee', '20');


-- #####################################################################
-- ##  PART 2 : SAMPLE DATA (DML)
-- #####################################################################

INSERT INTO areas (area_name,city,pincode) VALUES
('Chandni Chowk','Delhi','110006'),
('Hauz Khas','Delhi','110016'),
('Lajpat Nagar','Delhi','110024'),
('Connaught Place','Delhi','110001'),
('Karol Bagh','Delhi','110005'),
('Nizamuddin','Delhi','110013'),
('Sector 29','Gurugram','122001'),
('Sector 14','Gurugram','122007'),
('Sukhrali (KRMU)','Gurugram','122003'),
('Dwarka Sector 12','Delhi','110078');

INSERT INTO menu_categories (category_name) VALUES
('Starters'),
('Main Course'),
('Breads & Rice'),
('Snacks'),
('Beverages'),
('Desserts');

INSERT INTO users (full_name,email,phone,password_hash,user_type,created_at) VALUES
('Aarav Sharma','aarav.sharma@example.com','9810007919','hash_1001x','CUSTOMER','2026-08-02 10:00:00'),
('Riya Verma','riya.verma@example.com','9810015838','hash_1002x','CUSTOMER','2026-08-03 10:00:00'),
('Kabir Singh','kabir.singh@example.com','9810023757','hash_1003x','CUSTOMER','2026-08-04 10:00:00'),
('Ananya Gupta','ananya.gupta@example.com','9810031676','hash_1004x','CUSTOMER','2026-08-05 10:00:00'),
('Rohan Mehta','rohan.mehta@example.com','9810039595','hash_1005x','CUSTOMER','2026-08-06 10:00:00'),
('Ishita Kapoor','ishita.kapoor@example.com','9810047514','hash_1006x','CUSTOMER','2026-08-07 10:00:00'),
('Vikram Malhotra','vikram.malhotra@example.com','9810055433','hash_1007x','CUSTOMER','2026-08-08 10:00:00'),
('Sneha Reddy','sneha.reddy@example.com','9810063352','hash_1008x','CUSTOMER','2026-08-09 10:00:00'),
('Arjun Nair','arjun.nair@example.com','9810071271','hash_1009x','CUSTOMER','2026-08-10 10:00:00'),
('Pooja Yadav','pooja.yadav@example.com','9810079190','hash_1010x','CUSTOMER','2026-08-11 10:00:00'),
('Dev Chauhan','dev.chauhan@example.com','9810087109','hash_1011x','CUSTOMER','2026-08-12 10:00:00'),
('Simran Kaur','simran.kaur@example.com','9810095028','hash_1012x','CUSTOMER','2026-08-13 10:00:00'),
('Manav Arora','manav.arora@example.com','9810102947','hash_1013x','CUSTOMER','2026-08-14 10:00:00'),
('Tanvi Bansal','tanvi.bansal@example.com','9810110866','hash_1014x','CUSTOMER','2026-08-15 10:00:00'),
('Ramesh Kumar','ramesh.kumar@example.com','9810118785','hash_1015x','PARTNER','2026-08-16 10:00:00'),
('Sunil Rawat','sunil.rawat@example.com','9810126704','hash_1016x','PARTNER','2026-08-17 10:00:00'),
('Imran Khan','imran.khan@example.com','9810134623','hash_1017x','PARTNER','2026-08-18 10:00:00'),
('Deepak Thakur','deepak.thakur@example.com','9810142542','hash_1018x','PARTNER','2026-08-19 10:00:00'),
('Mohit Saini','mohit.saini@example.com','9810150461','hash_1019x','PARTNER','2026-08-20 10:00:00'),
('Faiz Ahmed','faiz.ahmed@example.com','9810158380','hash_1020x','PARTNER','2026-08-21 10:00:00'),
('Harpreet Bedi','harpreet.bedi@example.com','9810166299','hash_1021x','OWNER','2026-08-22 10:00:00'),
('Lakshmi Iyer','lakshmi.iyer@example.com','9810174218','hash_1022x','OWNER','2026-08-23 10:00:00'),
('Naveen Jindal','naveen.jindal@example.com','9810182137','hash_1023x','OWNER','2026-08-24 10:00:00'),
('Salma Qureshi','salma.qureshi@example.com','9810190056','hash_1024x','OWNER','2026-08-25 10:00:00'),
('Gaurav Tandon','gaurav.tandon@example.com','9810197975','hash_1025x','OWNER','2026-08-01 10:00:00'),
('Meenakshi Rao','meenakshi.rao@example.com','9810205894','hash_1026x','OWNER','2026-08-02 10:00:00'),
('Ashok Gulati','ashok.gulati@example.com','9810213813','hash_1027x','OWNER','2026-08-03 10:00:00');

INSERT INTO customers (customer_id,wallet_balance,loyalty_points) VALUES
(1,0.00,280),(2,120.00,251),(3,400.00,300),(4,400.00,225),(5,650.00,122),
(6,800.00,1),(7,0.00,41),(8,50.00,56),(9,400.00,147),(10,400.00,50),
(11,400.00,230),(12,250.00,5),(13,800.00,251),(14,400.00,160);

INSERT INTO delivery_partners (partner_id,vehicle_type,vehicle_no,is_available,joined_on) VALUES
(15,'BIKE','DL3SA1000',1,'2026-03-10'),
(16,'SCOOTER','DL4SB1037',1,'2026-04-11'),
(17,'BIKE','DL5SA1074',1,'2026-05-12'),
(18,'SCOOTER','DL6SB1111',1,'2026-06-13'),
(19,'CYCLE','DL7SA1148',1,'2026-03-14'),
(20,'BIKE','DL8SB1185',0,'2026-04-15');

INSERT INTO restaurant_owners (owner_id,gst_no) VALUES
(21,'07AAAPL1200A1Z0'),(22,'07AAAPL1211A1Z1'),(23,'07AAAPL1222A1Z2'),
(24,'07AAAPL1233A1Z3'),(25,'07AAAPL1244A1Z4'),(26,'07AAAPL1255A1Z5'),
(27,'07AAAPL1266A1Z6');

INSERT INTO addresses (customer_id,area_id,address_line,label) VALUES
(1,9,'Room 305, Boys Hostel','HOSTEL'),
(2,6,'3rd Floor, Tower C','HOME'),
(2,9,'B-45, Phase 2','HOSTEL'),
(3,9,'Flat 12, Gali No. 4','HOSTEL'),
(4,5,'3rd Floor, Tower C','HOME'),
(4,3,'B-45, Phase 2','HOSTEL'),
(5,9,'B-45, Phase 2','HOSTEL'),
(5,6,'Room 305, Boys Hostel','HOSTEL'),
(6,7,'Flat 12, Gali No. 4','HOME'),
(6,7,'Shop 7, Main Market','HOSTEL'),
(7,2,'3rd Floor, Tower C','HOME'),
(7,9,'Shop 7, Main Market','HOSTEL'),
(8,7,'Shop 7, Main Market','HOME'),
(8,5,'3rd Floor, Tower C','HOSTEL'),
(9,9,'Shop 7, Main Market','HOME'),
(9,1,'Shop 7, Main Market','HOSTEL'),
(10,9,'Flat 12, Gali No. 4','HOSTEL'),
(11,10,'3rd Floor, Tower C','HOME'),
(12,3,'3rd Floor, Tower C','HOME'),
(12,4,'Flat 12, Gali No. 4','HOSTEL'),
(13,8,'B-45, Phase 2','HOME'),
(13,9,'Room 305, Boys Hostel','HOSTEL'),
(14,5,'Shop 7, Main Market','HOME'),
(14,9,'B-45, Phase 2','HOSTEL');

INSERT INTO restaurants (owner_id,area_id,name,cuisine,opens_at,closes_at,is_active,created_at) VALUES
(21,1,'Dilli Darbar Mughlai','Mughlai','12:00:00','23:59:00',1,'2026-02-10'),
(21,1,'Paranthe Wali Gali Co.','North Indian','07:00:00','22:00:00',1,'2026-03-10'),
(22,2,'Hauz Khas Social Bowl','Continental','11:00:00','01:00:00',1,'2026-04-10'),
(23,9,'Midnight Maggi Point','Snacks','18:00:00','04:00:00',1,'2026-05-10'),
(24,7,'Gurgaon Tandoor Tales','Tandoor','12:00:00','23:30:00',1,'2026-06-10'),
(25,3,'South Express','South Indian','08:00:00','22:30:00',1,'2026-02-10'),
(26,6,'Biryani Blues','Biryani','11:00:00','02:00:00',1,'2026-03-10'),
(26,8,'Momo Mafia','Momos','12:00:00','23:00:00',1,'2026-04-10'),
(27,4,'The Pizza Gully','Pizza','11:00:00','23:00:00',1,'2026-05-10'),
(22,5,'Sweet Tooth Mithai House','Desserts','09:00:00','22:00:00',1,'2026-06-10');

INSERT INTO menu_items (restaurant_id,category_id,item_name,description,price,is_veg,is_available,stock_qty) VALUES
(1,1,'Seekh Kebab','Minced lamb, charcoal grilled',280.00,0,1,NULL),
(1,2,'Butter Chicken','Creamy tomato gravy, tandoori chicken',420.00,0,1,NULL),
(1,2,'Mutton Nihari','Slow cooked overnight, limited daily batch',520.00,0,1,8),
(1,2,'Dal Makhani','Black lentils simmered 12 hours',260.00,1,1,NULL),
(1,3,'Garlic Naan','Tandoor baked, garlic butter',70.00,1,1,NULL),
(1,3,'Sheermal','Saffron flavoured sweet bread',80.00,1,1,NULL),
(2,2,'Aloo Paratha','Stuffed with spiced potato, white butter',90.00,1,1,NULL),
(2,2,'Paneer Paratha','Stuffed with crumbled paneer',120.00,1,1,NULL),
(2,2,'Gobhi Paratha','Cauliflower and ajwain',100.00,1,1,NULL),
(2,6,'Rabri Falooda','Thick rabri, rose syrup, vermicelli',140.00,1,1,NULL),
(2,5,'Masala Chai','Kadak, ginger and elaichi',40.00,1,1,NULL),
(3,2,'Burrito Bowl','Rice, beans, grilled chicken, salsa',330.00,0,1,NULL),
(3,2,'Falafel Bowl','Falafel, hummus, pickled veg',290.00,1,1,NULL),
(3,4,'Loaded Nachos','Cheese, jalapeno, salsa',240.00,1,1,NULL),
(3,5,'Cold Coffee','Thick and frothy',150.00,1,1,NULL),
(3,6,'Brownie Sundae','Warm brownie, vanilla ice cream',190.00,1,1,NULL),
(4,4,'Masala Maggi','The hostel classic',80.00,1,1,NULL),
(4,4,'Cheese Maggi','Extra cheesy',110.00,1,1,NULL),
(4,4,'Egg Maggi','Scrambled egg and masala',100.00,0,1,NULL),
(4,4,'Bun Omelette','Double egg, toasted bun',90.00,0,1,NULL),
(4,5,'Iced Tea','Lemon iced tea',70.00,1,1,NULL),
(4,4,'French Fries','Peri peri dust',100.00,1,1,NULL),
(5,1,'Tandoori Chicken','Half chicken, smoky',360.00,0,1,NULL),
(5,1,'Paneer Tikka','Mint marinated paneer',290.00,1,1,NULL),
(5,2,'Chicken Tikka Masala','Rich onion tomato gravy',380.00,0,1,NULL),
(5,3,'Lachha Paratha','Layered tandoor paratha',60.00,1,1,NULL),
(5,5,'Mint Lemonade','Fresh and chilled',90.00,1,1,NULL),
(6,2,'Masala Dosa','Crisp dosa, potato filling',130.00,1,1,NULL),
(6,2,'Idli Sambar','Three soft idlis',90.00,1,1,NULL),
(6,4,'Medu Vada','Crispy lentil donuts',80.00,1,1,NULL),
(6,5,'Filter Coffee','Decoction coffee',60.00,1,1,NULL),
(6,6,'Rava Kesari','Semolina sweet',70.00,1,1,NULL),
(7,2,'Chicken Dum Biryani','Sealed handi, 6 hour marination',340.00,0,1,NULL),
(7,2,'Mutton Biryani','Slow cooked, saffron rice',460.00,0,1,12),
(7,2,'Veg Biryani','Seasonal vegetables, kewra',240.00,1,1,NULL),
(7,1,'Chicken 65','Spicy fried chicken',260.00,0,1,NULL),
(7,3,'Boondi Raita','Cool curd with boondi',60.00,1,1,NULL),
(7,6,'Phirni','Ground rice pudding in clay bowl',110.00,1,1,NULL),
(8,4,'Steamed Veg Momos','Six pieces with chutney',120.00,1,1,NULL),
(8,4,'Chicken Peri Peri Momos','Six pieces, spicy',160.00,0,1,NULL),
(8,4,'Tandoori Momos','Charred in the tandoor',180.00,0,1,NULL),
(8,2,'Thukpa','Himalayan noodle soup',210.00,0,1,NULL),
(8,6,'Chocolate Momos','Molten chocolate filling',130.00,1,1,NULL),
(9,2,'Margherita Pizza','Classic tomato mozzarella',249.00,1,1,NULL),
(9,2,'Peppy Paneer Pizza','Paneer, capsicum, red paprika',329.00,1,1,NULL),
(9,2,'Chicken Sausage Pizza','Loaded with sausage',369.00,0,1,NULL),
(9,1,'Garlic Bread','Cheesy garlic bread',140.00,1,1,NULL),
(9,6,'Choco Lava Cake','Gooey centre',120.00,1,1,20),
(9,5,'Cola','300 ml',60.00,1,1,NULL),
(10,6,'Gulab Jamun Box','Box of 8, warm',220.00,1,1,NULL),
(10,6,'Kaju Katli 500g','Cashew fudge',550.00,1,1,NULL),
(10,6,'Jalebi','Fresh from the kadhai',120.00,1,1,NULL),
(10,4,'Samosa Chaat','Crushed samosa, chutneys, curd',90.00,1,1,NULL);

INSERT INTO coupons (code,discount_pct,max_discount,min_order_value,valid_from,valid_to,max_uses_per_customer) VALUES
('WELCOME50',50,100.00,199.00,'2026-09-01','2027-12-31',1),
('DILLI20',20,80.00,299.00,'2026-09-01','2027-12-31',3),
('LATENIGHT',15,60.00,149.00,'2026-09-01','2027-12-31',2);

INSERT INTO orders (customer_id,restaurant_id,address_id,coupon_id,order_time,status,subtotal,discount_amt,delivery_fee,total_amt) VALUES
(4,7,5,1,'2026-09-01 14:37:00','DELIVERED',1000.00,100.00,0.00,900.00),
(3,2,4,1,'2026-09-02 19:57:00','DELIVERED',850.00,100.00,0.00,750.00),
(4,7,5,2,'2026-09-02 20:15:00','DELIVERED',1600.00,80.00,0.00,1520.00),
(6,6,10,2,'2026-09-03 12:33:00','DELIVERED',520.00,80.00,0.00,440.00),
(9,8,16,NULL,'2026-09-04 14:10:00','DELIVERED',1220.00,0.00,0.00,1220.00),
(7,1,12,1,'2026-09-07 19:48:00','CANCELLED',1940.00,100.00,0.00,1840.00),
(3,5,4,NULL,'2026-09-09 14:20:00','CANCELLED',1860.00,0.00,0.00,1860.00),
(13,6,22,2,'2026-09-11 20:12:00','DELIVERED',350.00,70.00,30.00,310.00),
(6,3,9,1,'2026-09-13 13:54:00','DELIVERED',1880.00,100.00,0.00,1780.00),
(10,3,17,1,'2026-09-13 23:01:00','DELIVERED',1320.00,100.00,0.00,1220.00),
(10,5,17,NULL,'2026-09-15 13:07:00','CANCELLED',2020.00,0.00,0.00,2020.00),
(4,7,6,2,'2026-09-16 14:26:00','DELIVERED',2080.00,80.00,0.00,2000.00),
(4,3,6,NULL,'2026-09-16 19:29:00','DELIVERED',570.00,0.00,0.00,570.00),
(5,6,7,1,'2026-09-16 21:55:00','DELIVERED',300.00,100.00,30.00,230.00),
(5,3,7,1,'2026-09-17 19:24:00','DELIVERED',1740.00,100.00,0.00,1640.00),
(12,2,19,NULL,'2026-09-18 13:54:00','DELIVERED',200.00,0.00,30.00,230.00),
(10,6,17,NULL,'2026-09-20 20:13:00','DELIVERED',250.00,0.00,30.00,280.00),
(13,3,21,1,'2026-09-22 12:03:00','DELIVERED',1590.00,100.00,0.00,1490.00),
(10,7,17,NULL,'2026-09-24 20:06:00','DELIVERED',780.00,0.00,0.00,780.00),
(6,5,9,NULL,'2026-09-26 13:31:00','DELIVERED',1810.00,0.00,0.00,1810.00),
(2,4,3,2,'2026-09-26 19:06:00','DELIVERED',900.00,80.00,0.00,820.00),
(3,5,4,NULL,'2026-09-26 19:29:00','DELIVERED',2220.00,0.00,0.00,2220.00),
(4,1,6,2,'2026-09-26 20:11:00','DELIVERED',1290.00,80.00,0.00,1210.00),
(1,3,1,NULL,'2026-09-28 13:05:00','DELIVERED',540.00,0.00,0.00,540.00),
(10,4,17,NULL,'2026-09-29 21:11:00','DELIVERED',770.00,0.00,0.00,770.00),
(14,5,23,NULL,'2026-10-03 19:52:00','DELIVERED',990.00,0.00,0.00,990.00),
(7,9,11,NULL,'2026-10-04 14:33:00','DELIVERED',678.00,0.00,0.00,678.00),
(10,9,17,2,'2026-10-07 19:20:00','DELIVERED',1925.00,80.00,0.00,1845.00),
(1,7,1,1,'2026-10-08 14:58:00','DELIVERED',1460.00,100.00,0.00,1360.00),
(2,1,2,NULL,'2026-10-09 19:46:00','DELIVERED',630.00,0.00,0.00,630.00),
(5,5,7,2,'2026-10-11 12:40:00','DELIVERED',1630.00,80.00,0.00,1550.00),
(1,4,1,NULL,'2026-10-15 20:59:00','DELIVERED',200.00,0.00,30.00,230.00),
(2,1,3,1,'2026-10-16 20:41:00','CANCELLED',500.00,100.00,0.00,400.00),
(12,7,19,1,'2026-10-17 23:14:00','DELIVERED',400.00,100.00,30.00,330.00),
(1,7,1,2,'2026-10-22 14:13:00','DELIVERED',780.00,80.00,0.00,700.00),
(2,6,2,2,'2026-10-23 12:57:00','DELIVERED',540.00,80.00,0.00,460.00),
(8,8,14,1,'2026-10-23 20:53:00','DELIVERED',1070.00,100.00,0.00,970.00),
(4,7,5,NULL,'2026-10-24 20:59:00','DELIVERED',1660.00,0.00,0.00,1660.00),
(12,5,20,2,'2026-10-26 13:53:00','DELIVERED',2190.00,80.00,0.00,2110.00),
(10,4,17,NULL,'2026-10-26 22:18:00','DELIVERED',590.00,0.00,0.00,590.00),
(4,8,5,NULL,'2026-10-29 20:41:00','DELIVERED',690.00,0.00,0.00,690.00),
(14,9,23,1,'2026-11-01 22:41:00','DELIVERED',660.00,100.00,0.00,560.00),
(13,6,21,NULL,'2026-11-02 21:08:00','DELIVERED',140.00,0.00,30.00,170.00),
(10,4,17,NULL,'2026-11-03 21:35:00','DELIVERED',420.00,0.00,30.00,450.00),
(5,8,7,NULL,'2026-11-05 13:59:00','DELIVERED',320.00,0.00,30.00,350.00),
(1,7,1,NULL,'2026-11-05 19:43:00','DELIVERED',2160.00,0.00,0.00,2160.00),
(14,4,24,NULL,'2026-11-05 22:59:00','DELIVERED',480.00,0.00,30.00,510.00),
(4,9,6,NULL,'2026-11-06 21:42:00','DELIVERED',2125.00,0.00,0.00,2125.00),
(4,1,6,NULL,'2026-11-06 21:50:00','DELIVERED',560.00,0.00,0.00,560.00),
(5,5,7,NULL,'2026-11-07 21:50:00','DELIVERED',890.00,0.00,0.00,890.00),
(3,2,4,2,'2026-11-08 19:05:00','DELIVERED',500.00,80.00,0.00,420.00),
(9,5,16,1,'2026-11-09 20:25:00','DELIVERED',580.00,100.00,0.00,480.00),
(12,3,19,3,'2026-11-09 23:12:00','DELIVERED',1190.00,60.00,0.00,1130.00),
(8,3,13,3,'2026-11-09 23:42:00','DELIVERED',580.00,60.00,0.00,520.00),
(3,3,4,NULL,'2026-11-11 12:50:00','DELIVERED',690.00,0.00,0.00,690.00),
(2,1,3,2,'2026-11-11 20:59:00','DELIVERED',1970.00,80.00,0.00,1890.00),
(7,7,12,2,'2026-11-12 21:36:00','DELIVERED',2500.00,80.00,0.00,2420.00),
(11,5,18,NULL,'2026-11-14 14:02:00','DELIVERED',2220.00,0.00,0.00,2220.00),
(10,1,17,NULL,'2026-11-15 14:26:00','DELIVERED',2320.00,0.00,0.00,2320.00),
(1,3,1,3,'2026-11-16 23:51:00','DELIVERED',1350.00,60.00,0.00,1290.00),
(2,2,3,2,'2026-11-18 12:10:00','PLACED',1060.00,80.00,0.00,980.00),
(4,9,6,NULL,'2026-11-18 12:25:00','PREPARING',1427.00,0.00,0.00,1427.00),
(7,2,11,2,'2026-11-18 12:40:00','OUT_FOR_DELIVERY',640.00,80.00,0.00,560.00);

INSERT INTO order_items (order_id,item_id,quantity,unit_price) VALUES
(1,38,2,110.00),(1,36,3,260.00),(2,10,3,140.00),(2,9,3,100.00),(2,11,1,40.00),(2,7,1,90.00),
(3,34,2,460.00),(3,33,2,340.00),(4,28,2,130.00),(4,32,2,70.00),(4,31,2,60.00),(5,42,2,210.00),
(5,41,1,180.00),(5,39,3,120.00),(5,43,2,130.00),(6,2,3,420.00),(6,3,1,520.00),(6,6,2,80.00),
(7,23,2,360.00),(7,25,1,380.00),(7,26,3,60.00),(7,24,2,290.00),(8,28,1,130.00),(8,31,1,60.00),
(8,30,2,80.00),(9,14,3,240.00),(9,12,1,330.00),(9,15,3,150.00),(9,16,2,190.00),(10,15,3,150.00),
(10,13,3,290.00),(11,25,3,380.00),(11,27,2,90.00),(11,24,2,290.00),(11,26,2,60.00),(12,34,2,460.00),
(12,33,2,340.00),(12,36,1,260.00),(12,38,2,110.00),(13,16,3,190.00),(14,30,3,80.00),(14,31,1,60.00),
(15,14,3,240.00),(15,15,3,150.00),(15,16,3,190.00),(16,9,2,100.00),(17,31,3,60.00),(17,32,1,70.00),
(18,14,3,240.00),(18,13,3,290.00),(19,36,3,260.00),(20,24,3,290.00),(20,25,2,380.00),(20,26,3,60.00),
(21,17,3,80.00),(21,21,2,70.00),(21,18,2,110.00),(21,19,3,100.00),(22,27,2,90.00),(22,23,3,360.00),
(22,25,1,380.00),(22,24,2,290.00),(23,5,1,70.00),(23,1,1,280.00),(23,2,1,420.00),(23,4,2,260.00),
(24,14,1,240.00),(24,15,2,150.00),(25,21,2,70.00),(25,17,3,80.00),(25,20,1,90.00),(25,22,3,100.00),
(26,27,3,90.00),(26,23,2,360.00),(27,46,1,369.00),(27,44,1,249.00),(27,49,1,60.00),(28,48,3,120.00),
(28,44,2,249.00),(28,45,1,329.00),(28,46,2,369.00),(29,36,3,260.00),(29,33,2,340.00),(30,2,1,420.00),
(30,5,3,70.00),(31,25,2,380.00),(31,24,3,290.00),(32,22,2,100.00),(33,6,3,80.00),(33,4,1,260.00),
(34,37,3,60.00),(34,38,2,110.00),(35,36,3,260.00),(36,30,2,80.00),(36,32,2,70.00),(36,29,2,90.00),
(36,31,1,60.00),(37,40,2,160.00),(37,39,1,120.00),(37,42,3,210.00),(38,33,2,340.00),(38,37,1,60.00),
(38,34,2,460.00),(39,26,3,60.00),(39,24,3,290.00),(39,25,3,380.00),(40,19,1,100.00),(40,17,1,80.00),
(40,21,2,70.00),(40,20,3,90.00),(41,43,1,130.00),(41,39,2,120.00),(41,40,2,160.00),(42,48,2,120.00),
(42,47,3,140.00),(43,32,2,70.00),(44,20,2,90.00),(44,17,3,80.00),(45,40,2,160.00),(46,35,2,240.00),
(46,33,2,340.00),(46,38,2,110.00),(46,36,3,260.00),(47,19,3,100.00),(47,22,1,100.00),(47,17,1,80.00),
(48,48,1,120.00),(48,46,2,369.00),(48,47,2,140.00),(48,45,3,329.00),(49,1,2,280.00),(50,23,1,360.00),
(50,27,2,90.00),(50,24,1,290.00),(50,26,1,60.00),(51,11,1,40.00),(51,10,2,140.00),(51,7,2,90.00),
(52,24,2,290.00),(53,12,2,330.00),(53,16,2,190.00),(53,15,1,150.00),(54,13,2,290.00),(55,14,1,240.00),
(55,15,3,150.00),(56,6,2,80.00),(56,1,2,280.00),(56,3,2,520.00),(56,5,3,70.00),(57,36,3,260.00),
(57,33,1,340.00),(57,34,3,460.00),(58,23,3,360.00),(58,25,3,380.00),(59,5,2,70.00),(59,1,3,280.00),
(59,6,1,80.00),(59,2,3,420.00),(60,12,1,330.00),(60,13,3,290.00),(60,15,1,150.00),(61,9,1,100.00),
(61,8,3,120.00),(61,10,3,140.00),(61,7,2,90.00),(62,48,2,120.00),(62,47,2,140.00),(62,45,2,329.00),
(62,44,1,249.00),(63,8,1,120.00),(63,9,1,100.00),(63,10,3,140.00);

INSERT INTO payments (order_id,method,pay_status,amount,paid_at) VALUES
(1,'COD','PAID',900.00,'2026-09-01 15:23:00'),
(2,'UPI','PAID',750.00,'2026-09-02 19:58:00'),
(3,'UPI','PAID',1520.00,'2026-09-02 20:16:00'),
(4,'UPI','PAID',440.00,'2026-09-03 12:34:00'),
(5,'UPI','PAID',1220.00,'2026-09-04 14:11:00'),
(6,'CARD','REFUNDED',1840.00,'2026-09-07 19:49:00'),
(7,'UPI','REFUNDED',1860.00,'2026-09-09 14:21:00'),
(8,'CARD','PAID',310.00,'2026-09-11 20:13:00'),
(9,'COD','PAID',1780.00,'2026-09-13 14:39:00'),
(10,'UPI','PAID',1220.00,'2026-09-13 23:02:00'),
(11,'UPI','REFUNDED',2020.00,'2026-09-15 13:08:00'),
(12,'UPI','PAID',2000.00,'2026-09-16 14:27:00'),
(13,'UPI','PAID',570.00,'2026-09-16 19:30:00'),
(14,'UPI','PAID',230.00,'2026-09-16 21:56:00'),
(15,'UPI','PAID',1640.00,'2026-09-17 19:25:00'),
(16,'UPI','PAID',230.00,'2026-09-18 13:55:00'),
(17,'UPI','PAID',280.00,'2026-09-20 20:14:00'),
(18,'UPI','PAID',1490.00,'2026-09-22 12:04:00'),
(19,'UPI','PAID',780.00,'2026-09-24 20:07:00'),
(20,'WALLET','PAID',1810.00,'2026-09-26 13:32:00'),
(21,'WALLET','PAID',820.00,'2026-09-26 19:07:00'),
(22,'COD','PAID',2220.00,'2026-09-26 20:16:00'),
(23,'UPI','PAID',1210.00,'2026-09-26 20:12:00'),
(24,'UPI','PAID',540.00,'2026-09-28 13:06:00'),
(25,'UPI','PAID',770.00,'2026-09-29 21:12:00'),
(26,'UPI','PAID',990.00,'2026-10-03 19:53:00'),
(27,'WALLET','PAID',678.00,'2026-10-04 14:34:00'),
(28,'UPI','PAID',1845.00,'2026-10-07 19:21:00'),
(29,'UPI','PAID',1360.00,'2026-10-08 14:59:00'),
(30,'UPI','PAID',630.00,'2026-10-09 19:47:00'),
(31,'COD','PAID',1550.00,'2026-10-11 13:26:00'),
(32,'UPI','PAID',230.00,'2026-10-15 21:00:00'),
(33,'COD','FAILED',400.00,NULL),
(34,'UPI','PAID',330.00,'2026-10-17 23:15:00'),
(35,'UPI','PAID',700.00,'2026-10-22 14:14:00'),
(36,'UPI','PAID',460.00,'2026-10-23 12:58:00'),
(37,'UPI','PAID',970.00,'2026-10-23 20:54:00'),
(38,'UPI','PAID',1660.00,'2026-10-24 21:00:00'),
(39,'COD','PAID',2110.00,'2026-10-26 14:49:00'),
(40,'UPI','PAID',590.00,'2026-10-26 22:19:00'),
(41,'WALLET','PAID',690.00,'2026-10-29 20:42:00'),
(42,'UPI','PAID',560.00,'2026-11-01 22:42:00'),
(43,'UPI','PAID',170.00,'2026-11-02 21:09:00'),
(44,'UPI','PAID',450.00,'2026-11-03 21:36:00'),
(45,'UPI','PAID',350.00,'2026-11-05 14:00:00'),
(46,'UPI','PAID',2160.00,'2026-11-05 19:44:00'),
(47,'COD','PAID',510.00,'2026-11-05 23:36:00'),
(48,'COD','PAID',2125.00,'2026-11-06 22:27:00'),
(49,'UPI','PAID',560.00,'2026-11-06 21:51:00'),
(50,'WALLET','PAID',890.00,'2026-11-07 21:51:00'),
(51,'CARD','PAID',420.00,'2026-11-08 19:06:00'),
(52,'CARD','PAID',480.00,'2026-11-09 20:26:00'),
(53,'WALLET','PAID',1130.00,'2026-11-09 23:13:00'),
(54,'UPI','PAID',520.00,'2026-11-09 23:43:00'),
(55,'COD','PAID',690.00,'2026-11-11 13:36:00'),
(56,'UPI','PAID',1890.00,'2026-11-11 21:00:00'),
(57,'UPI','PAID',2420.00,'2026-11-12 21:37:00'),
(58,'COD','PAID',2220.00,'2026-11-14 14:57:00'),
(59,'UPI','PAID',2320.00,'2026-11-15 14:27:00'),
(60,'UPI','PAID',1290.00,'2026-11-16 23:52:00'),
(61,'UPI','PAID',980.00,'2026-11-18 12:11:00'),
(62,'UPI','PAID',1427.00,'2026-11-18 12:26:00'),
(63,'UPI','PAID',560.00,'2026-11-18 12:41:00');

INSERT INTO deliveries (order_id,partner_id,picked_at,delivered_at,distance_km) VALUES
(1,16,'2026-09-01 14:52:00','2026-09-01 15:23:00',4.1),
(2,15,'2026-09-02 20:07:00','2026-09-02 20:37:00',9.9),
(3,19,'2026-09-02 20:34:00','2026-09-02 21:02:00',10.6),
(4,19,'2026-09-03 12:53:00','2026-09-03 13:22:00',4.5),
(5,18,'2026-09-04 14:24:00','2026-09-04 14:44:00',2.4),
(8,19,'2026-09-11 20:35:00','2026-09-11 21:03:00',9.8),
(9,19,'2026-09-13 14:12:00','2026-09-13 14:39:00',6.9),
(10,18,'2026-09-13 23:15:00','2026-09-13 23:27:00',2.3),
(12,19,'2026-09-16 14:37:00','2026-09-16 15:11:00',8.7),
(13,17,'2026-09-16 19:50:00','2026-09-16 20:24:00',3.1),
(14,16,'2026-09-16 22:11:00','2026-09-16 22:30:00',2.5),
(15,19,'2026-09-17 19:38:00','2026-09-17 20:02:00',8.7),
(16,19,'2026-09-18 14:15:00','2026-09-18 14:48:00',8.3),
(17,17,'2026-09-20 20:25:00','2026-09-20 21:02:00',6.0),
(18,17,'2026-09-22 12:21:00','2026-09-22 12:55:00',6.4),
(19,18,'2026-09-24 20:22:00','2026-09-24 20:48:00',5.0),
(20,16,'2026-09-26 13:47:00','2026-09-26 14:16:00',8.6),
(21,17,'2026-09-26 19:31:00','2026-09-26 20:08:00',11.3),
(22,17,'2026-09-26 19:40:00','2026-09-26 20:16:00',6.6),
(23,15,'2026-09-26 20:23:00','2026-09-26 20:50:00',9.0),
(24,19,'2026-09-28 13:25:00','2026-09-28 13:50:00',7.3),
(25,19,'2026-09-29 21:31:00','2026-09-29 21:55:00',4.0),
(26,15,'2026-10-03 20:05:00','2026-10-03 20:28:00',11.3),
(27,19,'2026-10-04 14:44:00','2026-10-04 15:17:00',4.9),
(28,15,'2026-10-07 19:39:00','2026-10-07 19:59:00',10.7),
(29,16,'2026-10-08 15:09:00','2026-10-08 15:31:00',1.4),
(30,15,'2026-10-09 20:07:00','2026-10-09 20:36:00',11.3),
(31,15,'2026-10-11 13:05:00','2026-10-11 13:26:00',7.7),
(32,16,'2026-10-15 21:18:00','2026-10-15 21:40:00',11.4),
(34,19,'2026-10-17 23:33:00','2026-10-18 00:03:00',2.7),
(35,15,'2026-10-22 14:37:00','2026-10-22 14:57:00',9.8),
(36,17,'2026-10-23 13:19:00','2026-10-23 13:56:00',3.5),
(37,19,'2026-10-23 21:12:00','2026-10-23 21:48:00',5.1),
(38,18,'2026-10-24 21:24:00','2026-10-24 21:44:00',8.2),
(39,17,'2026-10-26 14:15:00','2026-10-26 14:49:00',6.6),
(40,16,'2026-10-26 22:39:00','2026-10-26 23:04:00',1.5),
(41,17,'2026-10-29 20:55:00','2026-10-29 21:24:00',7.8),
(42,16,'2026-11-01 23:05:00','2026-11-01 23:34:00',6.0),
(43,18,'2026-11-02 21:31:00','2026-11-02 21:57:00',6.3),
(44,17,'2026-11-03 21:50:00','2026-11-03 22:26:00',1.3),
(45,15,'2026-11-05 14:17:00','2026-11-05 14:34:00',10.1),
(46,19,'2026-11-05 20:07:00','2026-11-05 20:31:00',2.9),
(47,15,'2026-11-05 23:19:00','2026-11-05 23:36:00',6.0),
(48,15,'2026-11-06 22:03:00','2026-11-06 22:27:00',5.5),
(49,17,'2026-11-06 22:00:00','2026-11-06 22:35:00',3.6),
(50,15,'2026-11-07 22:12:00','2026-11-07 22:41:00',1.6),
(51,15,'2026-11-08 19:17:00','2026-11-08 19:32:00',9.7),
(52,16,'2026-11-09 20:41:00','2026-11-09 21:02:00',4.5),
(53,15,'2026-11-09 23:33:00','2026-11-09 23:53:00',6.9),
(54,16,'2026-11-10 00:00:00','2026-11-10 00:32:00',8.2),
(55,19,'2026-11-11 13:01:00','2026-11-11 13:36:00',10.8),
(56,18,'2026-11-11 21:11:00','2026-11-11 21:35:00',6.1),
(57,17,'2026-11-12 21:49:00','2026-11-12 22:23:00',9.8),
(58,15,'2026-11-14 14:22:00','2026-11-14 14:57:00',10.2),
(59,18,'2026-11-15 14:48:00','2026-11-15 15:21:00',10.1),
(60,15,'2026-11-17 00:04:00','2026-11-17 00:33:00',1.6),
(63,16,'2026-11-18 12:57:00',NULL,6.0);

INSERT INTO reviews (order_id,restaurant_rating,delivery_rating,comment,reviewed_at) VALUES
(1,4,2,'Piping hot and on time','2026-09-01 19:04:00'),
(2,4,5,'Value for money','2026-09-02 23:18:00'),
(3,4,2,'Loved it, will order again','2026-09-03 01:01:00'),
(5,4,5,'Cold by the time it arrived','2026-09-04 17:29:00'),
(9,4,4,'Could be spicier','2026-09-13 16:08:00'),
(10,4,4,'Cold by the time it arrived','2026-09-14 00:31:00'),
(12,3,3,'Best late night food in town','2026-09-16 17:19:00'),
(14,5,5,'Loved it, will order again','2026-09-16 23:09:00'),
(15,5,3,'Piping hot and on time','2026-09-17 23:32:00'),
(19,5,3,'Loved it, will order again','2026-09-25 00:32:00'),
(20,4,4,'Taste was average','2026-09-26 15:09:00'),
(21,4,3,'Delivery was quick','2026-09-26 22:09:00'),
(22,4,4,'Value for money','2026-09-26 22:17:00'),
(23,4,3,'Delivery was quick','2026-09-26 23:58:00'),
(24,5,4,'Value for money','2026-09-28 15:32:00'),
(25,4,3,'Value for money','2026-09-30 01:42:00'),
(26,3,5,'Could be spicier','2026-10-03 22:47:00'),
(28,4,4,'Cold by the time it arrived','2026-10-07 22:46:00'),
(29,5,4,'Could be spicier','2026-10-08 16:19:00'),
(30,5,4,'Loved it, will order again','2026-10-10 00:23:00'),
(31,3,5,'Portion was generous','2026-10-11 16:41:00'),
(32,3,4,'Piping hot and on time','2026-10-15 23:12:00'),
(35,4,5,'Best late night food in town','2026-10-22 16:54:00'),
(37,3,4,'Could be spicier','2026-10-24 00:03:00'),
(38,4,3,'Cold by the time it arrived','2026-10-24 23:15:00'),
(39,4,4,'Packaging was leaking a bit','2026-10-26 17:17:00'),
(40,4,4,'Portion was generous','2026-10-27 01:06:00'),
(43,4,4,'Piping hot and on time','2026-11-02 23:46:00'),
(44,3,3,'Taste was average','2026-11-04 01:52:00'),
(45,5,5,'Could be spicier','2026-11-05 16:54:00'),
(47,4,5,'Taste was average','2026-11-06 02:54:00'),
(48,5,5,'Cold by the time it arrived','2026-11-07 00:51:00'),
(49,5,2,'Value for money','2026-11-07 00:58:00'),
(50,5,4,'Best late night food in town','2026-11-08 00:30:00'),
(51,4,4,'Best late night food in town','2026-11-08 22:56:00'),
(53,4,5,'Cold by the time it arrived','2026-11-10 00:26:00'),
(54,3,3,'Packaging was leaking a bit','2026-11-10 01:25:00'),
(56,5,5,'Piping hot and on time','2026-11-11 21:57:00'),
(58,5,4,'Cold by the time it arrived','2026-11-14 16:30:00');


-- #####################################################################
-- ##  PART 4 : VIEWS AND INDEXES
-- #####################################################################

CREATE OR REPLACE VIEW v_order_details AS
SELECT o.order_id, o.order_time, o.status,
       cu.full_name  AS customer,
       r.name        AS restaurant,
       ar.area_name  AS delivery_area,
       o.subtotal, o.discount_amt, o.delivery_fee, o.total_amt,
       p.method      AS payment_method, p.pay_status,
       pu.full_name  AS delivery_partner
FROM orders o
JOIN users cu        ON cu.user_id = o.customer_id
JOIN restaurants r   ON r.restaurant_id = o.restaurant_id
JOIN addresses ad    ON ad.address_id = o.address_id
JOIN areas ar        ON ar.area_id = ad.area_id
LEFT JOIN payments p ON p.order_id = o.order_id
LEFT JOIN deliveries d ON d.order_id = o.order_id
LEFT JOIN users pu   ON pu.user_id = d.partner_id;

CREATE OR REPLACE VIEW v_restaurant_performance AS
SELECT r.restaurant_id, r.name, r.cuisine,
       COUNT(DISTINCT o.order_id)                       AS total_orders,
       COALESCE(SUM(CASE WHEN o.status='DELIVERED' THEN o.total_amt END),0) AS revenue,
       ROUND(AVG(rv.restaurant_rating),2)               AS avg_rating,
       SUM(o.status='CANCELLED')                        AS cancelled_orders
FROM restaurants r
LEFT JOIN orders o   ON o.restaurant_id = r.restaurant_id
LEFT JOIN reviews rv ON rv.order_id = o.order_id
GROUP BY r.restaurant_id, r.name, r.cuisine;

CREATE OR REPLACE VIEW v_high_value_customers AS
SELECT u.user_id AS customer_id, u.full_name, COUNT(*) AS orders,
       SUM(o.total_amt) AS total_spent
FROM orders o JOIN users u ON u.user_id = o.customer_id
WHERE o.status = 'DELIVERED'
GROUP BY u.user_id, u.full_name
HAVING SUM(o.total_amt) > 5000;

CREATE OR REPLACE VIEW v_late_night_restaurants AS
SELECT r.name, r.cuisine, a.area_name, r.opens_at, r.closes_at
FROM restaurants r JOIN areas a ON a.area_id = r.area_id
WHERE r.serves_after_midnight = 1 AND r.is_active = 1;

CREATE OR REPLACE VIEW v_partner_task_sheet AS
SELECT o.order_id, d.partner_id, r.name AS pickup_from,
       cu.full_name AS deliver_to, ad.address_line, ar.area_name
FROM orders o
JOIN deliveries d  ON d.order_id = o.order_id
JOIN restaurants r ON r.restaurant_id = o.restaurant_id
JOIN users cu      ON cu.user_id = o.customer_id
JOIN addresses ad  ON ad.address_id = o.address_id
JOIN areas ar      ON ar.area_id = ad.area_id
WHERE o.status = 'OUT_FOR_DELIVERY';

CREATE INDEX idx_orders_cust_time ON orders (customer_id, order_time);
CREATE INDEX idx_orders_rest_status ON orders (restaurant_id, status);
CREATE INDEX idx_oi_item ON order_items (item_id);
CREATE INDEX idx_menu_rest_veg ON menu_items (restaurant_id, is_veg, price);
CREATE INDEX idx_orders_time ON orders (order_time);
ALTER TABLE menu_items ADD FULLTEXT INDEX ft_item_search (item_name, description);


-- #####################################################################
-- ##  PART 5 : FUNCTIONS, TRIGGERS, PROCEDURES, ROLES
-- #####################################################################

DROP FUNCTION IF EXISTS fn_delivery_fee;
DELIMITER $$
CREATE FUNCTION fn_delivery_fee(p_subtotal DECIMAL(10,2))
RETURNS DECIMAL(10,2)
READS SQL DATA
BEGIN
    DECLARE v_fee   DECIMAL(10,2);
    DECLARE v_rain  VARCHAR(40);
    DECLARE v_surge VARCHAR(40);
    SET v_fee = IF(p_subtotal >= 500, 0, 30);
    SELECT setting_value INTO v_rain  FROM app_settings WHERE setting_key = 'is_raining';
    SELECT setting_value INTO v_surge FROM app_settings WHERE setting_key = 'rain_surge_fee';
    IF v_rain = '1' AND p_subtotal > 0 THEN
        SET v_fee = v_fee + CAST(v_surge AS DECIMAL(10,2));
    END IF;
    RETURN v_fee;
END$$
DELIMITER ;

DROP TRIGGER IF EXISTS trg_orders_coupon_limit;
DROP TRIGGER IF EXISTS trg_orders_status_log;
DROP TRIGGER IF EXISTS trg_oi_validate;
DROP TRIGGER IF EXISTS trg_reviews_delivered_only;

DELIMITER $$

CREATE TRIGGER trg_orders_coupon_limit BEFORE INSERT ON orders
FOR EACH ROW
BEGIN
    DECLARE v_used INT;
    DECLARE v_max  INT;
    IF NEW.coupon_id IS NOT NULL THEN
        SELECT max_uses_per_customer INTO v_max FROM coupons WHERE coupon_id = NEW.coupon_id;
        SELECT COUNT(*) INTO v_used FROM orders
         WHERE customer_id = NEW.customer_id AND coupon_id = NEW.coupon_id AND status <> 'CANCELLED';
        IF v_used >= v_max THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Coupon usage limit reached for this customer';
        END IF;
    END IF;
END$$

CREATE TRIGGER trg_orders_status_log AFTER UPDATE ON orders
FOR EACH ROW
BEGIN
    IF OLD.status <> NEW.status THEN
        INSERT INTO order_status_log (order_id, old_status, new_status)
        VALUES (NEW.order_id, OLD.status, NEW.status);
    END IF;
END$$

CREATE TRIGGER trg_oi_validate BEFORE INSERT ON order_items
FOR EACH ROW
BEGIN
    DECLARE v_rest_order INT;
    DECLARE v_rest_item  INT;
    DECLARE v_avail      BOOLEAN;
    SELECT restaurant_id INTO v_rest_order FROM orders WHERE order_id = NEW.order_id;
    SELECT restaurant_id, is_available INTO v_rest_item, v_avail FROM menu_items WHERE item_id = NEW.item_id;
    IF v_rest_order <> v_rest_item THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Item does not belong to the restaurant of this order';
    END IF;
    IF v_avail = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Item is currently unavailable';
    END IF;
END$$

CREATE TRIGGER trg_reviews_delivered_only BEFORE INSERT ON reviews
FOR EACH ROW
BEGIN
    DECLARE v_status VARCHAR(20);
    SELECT status INTO v_status FROM orders WHERE order_id = NEW.order_id;
    IF v_status <> 'DELIVERED' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only delivered orders can be reviewed';
    END IF;
END$$

DELIMITER ;

DROP PROCEDURE IF EXISTS sp_recalc_order;
DROP PROCEDURE IF EXISTS sp_place_order;
DROP PROCEDURE IF EXISTS sp_add_item;
DROP PROCEDURE IF EXISTS sp_checkout;
DROP PROCEDURE IF EXISTS sp_restaurant_report;

DELIMITER $$

CREATE PROCEDURE sp_recalc_order(IN p_order_id INT)
BEGIN
    DECLARE v_sub    DECIMAL(10,2);
    DECLARE v_disc   DECIMAL(10,2) DEFAULT 0;
    DECLARE v_coupon INT;
    SELECT COALESCE(SUM(quantity * unit_price), 0) INTO v_sub
      FROM order_items WHERE order_id = p_order_id;
    SELECT coupon_id INTO v_coupon FROM orders WHERE order_id = p_order_id;
    IF v_coupon IS NOT NULL THEN
        SELECT IF(v_sub >= min_order_value,
                  LEAST(ROUND(v_sub * discount_pct / 100, 2), max_discount), 0)
          INTO v_disc FROM coupons WHERE coupon_id = v_coupon;
    END IF;
    UPDATE orders
       SET subtotal = v_sub, discount_amt = v_disc,
           delivery_fee = fn_delivery_fee(v_sub),
           total_amt = v_sub - v_disc + fn_delivery_fee(v_sub)
     WHERE order_id = p_order_id;
END$$

CREATE PROCEDURE sp_place_order(IN p_cust INT, IN p_rest INT, IN p_addr INT,
                                IN p_code VARCHAR(20), OUT p_order_id INT)
BEGIN
    DECLARE v_coupon INT DEFAULT NULL;
    IF NOT EXISTS (SELECT 1 FROM addresses WHERE address_id = p_addr AND customer_id = p_cust) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Address does not belong to this customer';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM restaurants WHERE restaurant_id = p_rest AND is_active = 1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Restaurant is not accepting orders';
    END IF;
    IF p_code IS NOT NULL THEN
        SELECT coupon_id INTO v_coupon FROM coupons
         WHERE code = p_code AND CURDATE() BETWEEN valid_from AND valid_to;
        IF v_coupon IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid or expired coupon';
        END IF;
    END IF;
    INSERT INTO orders (customer_id, restaurant_id, address_id, coupon_id)
    VALUES (p_cust, p_rest, p_addr, v_coupon);
    SET p_order_id = LAST_INSERT_ID();
END$$

CREATE PROCEDURE sp_add_item(IN p_order_id INT, IN p_item_id INT, IN p_qty INT)
BEGIN
    DECLARE v_price  DECIMAL(8,2);
    DECLARE v_stock  INT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;
    START TRANSACTION;
    SELECT price, stock_qty INTO v_price, v_stock
      FROM menu_items WHERE item_id = p_item_id FOR UPDATE;
    IF v_stock IS NOT NULL AND v_stock < p_qty THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Sold out: not enough stock left';
    END IF;
    INSERT INTO order_items (order_id, item_id, quantity, unit_price)
    VALUES (p_order_id, p_item_id, p_qty, v_price)
    ON DUPLICATE KEY UPDATE quantity = quantity + p_qty;
    IF v_stock IS NOT NULL THEN
        UPDATE menu_items SET stock_qty = stock_qty - p_qty WHERE item_id = p_item_id;
    END IF;
    CALL sp_recalc_order(p_order_id);
    COMMIT;
END$$

CREATE PROCEDURE sp_checkout(IN p_order_id INT, IN p_method VARCHAR(10))
BEGIN
    DECLARE v_total  DECIMAL(10,2);
    DECLARE v_cust   INT;
    DECLARE v_status VARCHAR(20);
    DECLARE v_wallet DECIMAL(10,2);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;
    START TRANSACTION;
    SELECT total_amt, customer_id, status INTO v_total, v_cust, v_status
      FROM orders WHERE order_id = p_order_id FOR UPDATE;
    IF v_status <> 'PLACED' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Order has already been processed';
    END IF;
    IF v_total <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cart is empty';
    END IF;
    IF p_method = 'WALLET' THEN
        SELECT wallet_balance INTO v_wallet FROM customers WHERE customer_id = v_cust FOR UPDATE;
        IF v_wallet < v_total THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient wallet balance';
        END IF;
        UPDATE customers SET wallet_balance = wallet_balance - v_total WHERE customer_id = v_cust;
    END IF;
    INSERT INTO payments (order_id, method, pay_status, amount, paid_at)
    VALUES (p_order_id, p_method, IF(p_method = 'COD', 'PENDING', 'PAID'), v_total,
            IF(p_method = 'COD', NULL, NOW()));
    UPDATE orders SET status = 'PREPARING' WHERE order_id = p_order_id;
    UPDATE customers SET loyalty_points = loyalty_points + FLOOR(v_total / 10) WHERE customer_id = v_cust;
    COMMIT;
END$$

CREATE PROCEDURE sp_restaurant_report()
BEGIN
    DECLARE done     INT DEFAULT 0;
    DECLARE v_id     INT;
    DECLARE v_name   VARCHAR(80);
    DECLARE v_orders INT;
    DECLARE v_rev    DECIMAL(12,2);
    DECLARE cur CURSOR FOR SELECT restaurant_id, name FROM restaurants ORDER BY name;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

    DROP TEMPORARY TABLE IF EXISTS tmp_report;
    CREATE TEMPORARY TABLE tmp_report (restaurant VARCHAR(80), orders INT, revenue DECIMAL(12,2), grade CHAR(1));

    OPEN cur;
    read_loop: LOOP
        FETCH cur INTO v_id, v_name;
        IF done = 1 THEN LEAVE read_loop; END IF;
        SELECT COUNT(*), COALESCE(SUM(total_amt), 0) INTO v_orders, v_rev
          FROM orders WHERE restaurant_id = v_id AND status = 'DELIVERED';
        INSERT INTO tmp_report VALUES (v_name, v_orders, v_rev,
               CASE WHEN v_rev >= 10000 THEN 'A' WHEN v_rev >= 3000 THEN 'B' ELSE 'C' END);
    END LOOP;
    CLOSE cur;
    SELECT * FROM tmp_report ORDER BY revenue DESC;
END$$

DELIMITER ;

-- Seed one initial audit log entry via the stored procedures
SET @aarav_addr     = (SELECT address_id FROM addresses WHERE customer_id = 1 LIMIT 1);
SET @dum_biryani    = (SELECT item_id FROM menu_items WHERE item_name = 'Chicken Dum Biryani');
SET @mutton_biryani = (SELECT item_id FROM menu_items WHERE item_name = 'Mutton Biryani');

CALL sp_place_order(1, 7, @aarav_addr, 'DILLI20', @new_order);
CALL sp_add_item(@new_order, @dum_biryani, 2);
CALL sp_add_item(@new_order, @mutton_biryani, 1);
CALL sp_checkout(@new_order, 'UPI');

-- RBAC Roles and Users
DROP USER IF EXISTS 'app_customer'@'localhost', 'app_partner'@'localhost',
                    'app_owner'@'localhost',    'app_analyst'@'localhost', 'app_admin'@'localhost';
DROP ROLE IF EXISTS role_customer, role_partner, role_owner, role_analyst, role_admin;

CREATE ROLE role_customer, role_partner, role_owner, role_analyst, role_admin;

GRANT SELECT ON dillibites.menu_items      TO role_customer;
GRANT SELECT ON dillibites.restaurants     TO role_customer;
GRANT SELECT ON dillibites.menu_categories TO role_customer;
GRANT EXECUTE ON PROCEDURE dillibites.sp_place_order TO role_customer;
GRANT EXECUTE ON PROCEDURE dillibites.sp_add_item    TO role_customer;
GRANT EXECUTE ON PROCEDURE dillibites.sp_checkout    TO role_customer;

GRANT SELECT ON dillibites.v_partner_task_sheet TO role_partner;
GRANT UPDATE (delivered_at) ON dillibites.deliveries TO role_partner;

GRANT SELECT ON dillibites.v_restaurant_performance TO role_owner;
GRANT SELECT, UPDATE (price, is_available, stock_qty) ON dillibites.menu_items TO role_owner;

GRANT SELECT ON dillibites.v_order_details          TO role_analyst;
GRANT SELECT ON dillibites.v_restaurant_performance TO role_analyst;
GRANT SELECT ON dillibites.v_high_value_customers   TO role_analyst;

GRANT ALL PRIVILEGES ON dillibites.* TO role_admin;

CREATE USER 'app_customer'@'localhost' IDENTIFIED BY 'Cust#Pass2026';
CREATE USER 'app_partner'@'localhost'  IDENTIFIED BY 'Part#Pass2026';
CREATE USER 'app_owner'@'localhost'    IDENTIFIED BY 'Own#Pass2026';
CREATE USER 'app_analyst'@'localhost'  IDENTIFIED BY 'Anly#Pass2026';
CREATE USER 'app_admin'@'localhost'    IDENTIFIED BY 'Admn#Pass2026';

GRANT role_customer TO 'app_customer'@'localhost';
GRANT role_partner  TO 'app_partner'@'localhost';
GRANT role_owner    TO 'app_owner'@'localhost';
GRANT role_analyst  TO 'app_analyst'@'localhost';
GRANT role_admin    TO 'app_admin'@'localhost';
SET DEFAULT ROLE ALL TO 'app_customer'@'localhost', 'app_partner'@'localhost', 'app_owner'@'localhost',
                        'app_analyst'@'localhost',  'app_admin'@'localhost';

REVOKE UPDATE (stock_qty) ON dillibites.menu_items FROM role_owner;


-- #####################################################################
-- ##  PART 6 : DATA WAREHOUSE (dillibites_dw)
-- #####################################################################

DROP DATABASE IF EXISTS dillibites_dw;
CREATE DATABASE dillibites_dw CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE dillibites_dw;

CREATE TABLE dim_date (
    date_key     INT PRIMARY KEY,
    full_date    DATE NOT NULL,
    day_name     VARCHAR(10) NOT NULL,
    month_no     TINYINT NOT NULL,
    month_name   VARCHAR(10) NOT NULL,
    quarter_no   TINYINT NOT NULL,
    year_no      SMALLINT NOT NULL,
    is_weekend   BOOLEAN NOT NULL
);

CREATE TABLE dim_customer (
    customer_key  INT PRIMARY KEY,
    full_name     VARCHAR(80) NOT NULL,
    signup_month  CHAR(7) NOT NULL
);

CREATE TABLE dim_restaurant (
    restaurant_key  INT PRIMARY KEY,
    name            VARCHAR(80) NOT NULL,
    cuisine         VARCHAR(40) NOT NULL,
    area_name       VARCHAR(60) NOT NULL,
    city            VARCHAR(40) NOT NULL,
    late_night      BOOLEAN NOT NULL
);

CREATE TABLE dim_partner (
    partner_key   INT PRIMARY KEY,
    full_name     VARCHAR(80) NOT NULL,
    vehicle_type  VARCHAR(10) NOT NULL
);

CREATE TABLE dim_payment (
    payment_key  INT AUTO_INCREMENT PRIMARY KEY,
    method       VARCHAR(10) NOT NULL UNIQUE
);

CREATE TABLE fact_orders (
    order_id          INT PRIMARY KEY,
    date_key          INT NOT NULL,
    hour_of_day       TINYINT NOT NULL,
    customer_key      INT NOT NULL,
    restaurant_key    INT NOT NULL,
    partner_key       INT NULL,
    payment_key       INT NULL,
    items_count       INT NOT NULL,
    subtotal          DECIMAL(10,2) NOT NULL,
    discount_amt      DECIMAL(10,2) NOT NULL,
    delivery_fee      DECIMAL(10,2) NOT NULL,
    total_amt         DECIMAL(10,2) NOT NULL,
    delivery_minutes  INT NULL,
    restaurant_rating TINYINT NULL,
    CONSTRAINT fk_f_date FOREIGN KEY (date_key)       REFERENCES dim_date(date_key),
    CONSTRAINT fk_f_cust FOREIGN KEY (customer_key)   REFERENCES dim_customer(customer_key),
    CONSTRAINT fk_f_rest FOREIGN KEY (restaurant_key) REFERENCES dim_restaurant(restaurant_key),
    CONSTRAINT fk_f_part FOREIGN KEY (partner_key)    REFERENCES dim_partner(partner_key),
    CONSTRAINT fk_f_pay  FOREIGN KEY (payment_key)    REFERENCES dim_payment(payment_key)
);

INSERT INTO dim_date
WITH RECURSIVE cal AS (
    SELECT DATE('2026-08-01') AS d
    UNION ALL SELECT d + INTERVAL 1 DAY FROM cal WHERE d < '2026-12-31'
)
SELECT CAST(DATE_FORMAT(d,'%Y%m%d') AS UNSIGNED), d, DAYNAME(d), MONTH(d), MONTHNAME(d),
       QUARTER(d), YEAR(d), (DAYOFWEEK(d) IN (1,7))
FROM cal;

INSERT INTO dim_customer
SELECT u.user_id, u.full_name, DATE_FORMAT(u.created_at,'%Y-%m')
FROM dillibites.users u WHERE u.user_type = 'CUSTOMER';

INSERT INTO dim_restaurant
SELECT r.restaurant_id, r.name, r.cuisine, a.area_name, a.city, r.serves_after_midnight
FROM dillibites.restaurants r JOIN dillibites.areas a ON a.area_id = r.area_id;

INSERT INTO dim_partner
SELECT dp.partner_id, u.full_name, dp.vehicle_type
FROM dillibites.delivery_partners dp JOIN dillibites.users u ON u.user_id = dp.partner_id;

INSERT INTO dim_payment (method) VALUES ('UPI'),('CARD'),('COD'),('WALLET');

INSERT INTO fact_orders
SELECT o.order_id,
       CAST(DATE_FORMAT(o.order_time,'%Y%m%d') AS UNSIGNED),
       HOUR(o.order_time),
       o.customer_id, o.restaurant_id, d.partner_id, dp.payment_key,
       (SELECT SUM(quantity) FROM dillibites.order_items oi WHERE oi.order_id = o.order_id),
       o.subtotal, o.discount_amt, o.delivery_fee, o.total_amt,
       TIMESTAMPDIFF(MINUTE, d.picked_at, d.delivered_at),
       rv.restaurant_rating
FROM dillibites.orders o
LEFT JOIN dillibites.deliveries d ON d.order_id = o.order_id
LEFT JOIN dillibites.payments   p ON p.order_id = o.order_id
LEFT JOIN dim_payment dp          ON dp.method = p.method
LEFT JOIN dillibites.reviews   rv ON rv.order_id = o.order_id
WHERE o.status = 'DELIVERED'
  AND EXISTS (SELECT 1 FROM dillibites.order_items oi WHERE oi.order_id = o.order_id);

-- Snowflake normalization tables
CREATE TABLE dim_area (
    area_key   INT AUTO_INCREMENT PRIMARY KEY,
    area_name  VARCHAR(60) NOT NULL,
    city       VARCHAR(40) NOT NULL,
    UNIQUE KEY uq_area (area_name, city)
);
INSERT INTO dim_area (area_name, city) SELECT DISTINCT area_name, city FROM dim_restaurant;

CREATE TABLE dim_restaurant_sf (
    restaurant_key INT PRIMARY KEY,
    name           VARCHAR(80) NOT NULL,
    cuisine        VARCHAR(40) NOT NULL,
    area_key       INT NOT NULL,
    late_night     BOOLEAN NOT NULL,
    CONSTRAINT fk_sf_area FOREIGN KEY (area_key) REFERENCES dim_area(area_key)
);
INSERT INTO dim_restaurant_sf
SELECT r.restaurant_key, r.name, r.cuisine, a.area_key, r.late_night
FROM dim_restaurant r JOIN dim_area a ON a.area_name = r.area_name AND a.city = r.city;

USE dillibites;