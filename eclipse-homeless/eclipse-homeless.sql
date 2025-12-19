-- Squatter ownership/progress
CREATE TABLE IF NOT EXISTS `qb_squatters` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `warehouse` VARCHAR(64) NOT NULL,
  `citizenid` VARCHAR(64) NOT NULL,
  `status` ENUM('squatting','owned') NOT NULL DEFAULT 'squatting',
  `minutes` INT NOT NULL DEFAULT 0,
  `claimed_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `owned_at` TIMESTAMP NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_warehouse` (`warehouse`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Homeless classification + welfare cooldown
CREATE TABLE IF NOT EXISTS `eclipse_homeless` (
  `citizenid` VARCHAR(64) NOT NULL,
  `is_homeless` TINYINT(1) NOT NULL DEFAULT 0,
  `last_welfare_date` VARCHAR(10) NULL DEFAULT NULL, -- YYYY-MM-DD
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
